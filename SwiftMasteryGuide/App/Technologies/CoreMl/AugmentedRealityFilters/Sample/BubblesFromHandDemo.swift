//
//  BubblesFromHandDemo.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 20/08/25.
//

import UIKit
import SwiftUI
import AVFoundation
import Vision
import CoreImage
import QuartzCore

// MARK: - Public SwiftUI screen

public struct ARBubblesDemoScreen: View {
    public init() {}

    public var body: some View {
        Representable()
            .ignoresSafeArea()
            .navigationTitle("AR Bubbles (Hand)")
            .navigationBarTitleDisplayMode(.inline)
    }

    private struct Representable: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> BubblesViewController {
            let vc = BubblesViewController()
            print("[SwiftUI] makeUIViewController OK")
            return vc
        }

        func updateUIViewController(_ uiViewController: BubblesViewController, context: Context) { }
    }
}

// MARK: - Main ViewController

final class BubblesViewController: UIViewController {

    // Camera
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()

    // Vision
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(label: "vision.handpose.queue")
    // Keeping sequenceHandler here is harmless, but we will use VNImageRequestHandler instead.

    // UI layers
    private let previewView = CameraPreviewView2()
    private let overlayView = BubbleEmitterView()

    // State
    private var isConfigured = false
    private var isRunning = false
    private var lastInference: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let minInferenceInterval: CFTimeInterval = 0.08 // ~12.5 fps throttling

    // Smoothing / debouncing for open-palm detection
    private var openPalmStableCounter = 0
    private var closedStableCounter = 0
    private let stableThreshold = 3 // frames

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        print("[VC] viewDidLoad")

        setupUI()
        requestCameraAccessAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
        overlayView.frame = view.bounds
    }

    // MARK: UI

    private func setupUI() {
        print("[UI] setupUI()")
        overlayView.isUserInteractionEnabled = false
        view.addSubview(previewView)
        view.addSubview(overlayView)
        print("[UI] added preview and overlay")
    }

    // MARK: Permissions + Start/Stop

    private func requestCameraAccessAndStart() {
        print("[VM] request camera permission")
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                print("[VM] camera already authorized")
                start()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            print("[VM] camera authorized")
                            self?.start()
                        } else {
                            print("[VM][ERR] camera denied by user")
                        }
                    }
                }
            case .denied, .restricted:
                print("[VM][ERR] camera access denied/restricted")
            @unknown default:
                print("[VM][ERR] unknown camera authorization status")
        }
    }

    private func start() {
        guard !isRunning else { return }
        print("[VM] start()")
        isRunning = true
        overlayView.start()
        configureSessionIfNeeded()
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            print("[Camera] session started")
        }
    }

    private func stop() {
        guard isRunning else { return }
        print("[VM] stop()")
        isRunning = false
        overlayView.stop()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            print("[Camera] session stopped")
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            self.session.beginConfiguration()
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.commitConfiguration()
            self.isConfigured = false
            print("[Camera] torn down")
        }
    }

    deinit {
        stop()
    }

    // MARK: Camera configuration

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        print("[Camera] configuring…")

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720 // more pixels for Vision → better landmarks

        // Input: FRONT camera (easier to debug hand near the device)
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            print("[Camera][ERR] could not create camera input")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(videoOutput) else {
            print("[Camera][ERR] cannot add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        // Orientation / rotation for portrait + mirror on front camera
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    print("[Camera] rotationAngle = 90° (portrait)")
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                print("[Camera] orientation = .portrait")
            }
            connection.isVideoMirrored = true
            print("[Camera] isVideoMirrored = true (front camera)")
        }

        // Preview
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill

        isConfigured = true
        session.commitConfiguration()
        print("[Camera] configured OK")
    }
}

// MARK: - Sample buffer delegate

extension BubblesViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRunning else { return }

        // Throttle
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastInference >= minInferenceInterval else { return }
        lastInference = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[Vision][ERR] no pixelBuffer")
            return
        }

        // Hand pose detection
        let request = handPoseRequest
        request.maximumHandCount = 1

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Use VNImageRequestHandler (no 'options' for CVPixelBuffer API)
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: self.currentCGImageOrientation(),
                    options: [:]
                )
                try handler.perform([request])

                let count = request.results?.count ?? 0
                print("[Vision] hand results count:", count, "revision:", request.revision)

                guard let observations = request.results, !observations.isEmpty else {
                    self.updateOpenPalmState(isOpen: false, reason: "no hand")
                    return
                }
                // Use best observation
                let best = observations.max(by: { $0.confidence < $1.confidence })
                if let best {
                    self.processHandObservation(best)
                } else {
                    self.updateOpenPalmState(isOpen: false, reason: "no best obs")
                }
            } catch {
                print("[Vision][ERR] perform failed: \(error)")
            }
        }
    }

    private func currentCGImageOrientation() -> CGImagePropertyOrientation {
        // Portrait + FRONT camera (mirrored)
        return .leftMirrored
        // If you switch back to the rear camera in portrait, use: return .right
    }

    private func processHandObservation(_ obs: VNHumanHandPoseObservation) {
        // Extract joint locations in normalized image coordinates [0,1]
        do {
            let points = try obs.recognizedPoints(.all)

            // Must have some confidence; relax for initial validation (0.1)
            func p(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                if let rp = points[j], rp.confidence > 0.1 {
                    // Convert Vision coords (origin bottom-left) to layer coords (origin top-left)
                    return CGPoint(x: CGFloat(rp.location.x), y: CGFloat(1 - rp.location.y))
                }
                return nil
            }

            guard let wrist = p(.wrist) else {
                updateOpenPalmState(isOpen: false, reason: "no wrist")
                return
            }

            struct Finger { let tip: CGPoint?; let mcp: CGPoint? }
            let fingers: [Finger] = [
                Finger(tip: p(.thumbTip),  mcp: p(.thumbCMC)),
                Finger(tip: p(.indexTip),  mcp: p(.indexMCP)),
                Finger(tip: p(.middleTip), mcp: p(.middleMCP)),
                Finger(tip: p(.ringTip),   mcp: p(.ringMCP)),
                Finger(tip: p(.littleTip), mcp: p(.littleMCP))
            ]

            var extendedCount = 0
            var tipPositions: [CGPoint] = []

            for f in fingers {
                if let tip = f.tip, let mcp = f.mcp {
                    let dm = hypot(tip.x - mcp.x, tip.y - mcp.y)
                    let dw = hypot(tip.x - wrist.x, tip.y - wrist.y)
                    // Relaxed thresholds to validate visually first:
                    if dw > 0.16, dm > 0.08 {
                        extendedCount += 1
                        tipPositions.append(tip)
                    }
                }
            }

            // Spread: average pairwise distance among tips
            var avgSpread: CGFloat = 0
            if tipPositions.count >= 3 {
                var sum: CGFloat = 0
                var n: CGFloat = 0
                for i in 0..<(tipPositions.count - 1) {
                    for j in (i + 1)..<tipPositions.count {
                        sum += hypot(tipPositions[i].x - tipPositions[j].x,
                                     tipPositions[i].y - tipPositions[j].y)
                        n += 1
                    }
                }
                if n > 0 { avgSpread = sum / n }
            }

            // Palm center ≈ average of MCPs
            var mcpList: [CGPoint] = []
            for name in [VNHumanHandPoseObservation.JointName.indexMCP,
                         .middleMCP, .ringMCP, .littleMCP, .thumbCMC] {
                if let v = p(name) { mcpList.append(v) }
            }
            let palmCenter = average(mcpList) ?? wrist

            // Simple facing + topology hints (for portrait + front camera)
            let wristToPalm = CGPoint(x: palmCenter.x - wrist.x, y: palmCenter.y - wrist.y)
            let wristToPalmUp = wristToPalm.y > 0 // Ajustado para refletir corretamente a direção da palma com base na orientação da câmera
            print("[Vision] wristToPalm.y:", wristToPalm.y, "→ wristToPalmUp:", wristToPalmUp)
            print("[Vision] wrist:", wrist)
            print("[Vision] palmCenter:", palmCenter)
            let tipsAbovePalm = tipPositions.filter { $0.y < palmCenter.y }.count

            // Final relaxed heuristic (so it triggers while you test):
            let isOpen: Bool =
            (extendedCount >= 3) &&      // was 5
            (avgSpread > 0.08) &&        // was 0.10
            wristToPalmUp &&
            (tipsAbovePalm >= 2)         // was 4

            print("[Vision] extended:", extendedCount,
                  "avgSpread:", String(format: "%.3f", avgSpread),
                  "tipsAbovePalm:", tipsAbovePalm,
                  "isOpen:", isOpen)

            updateOpenPalmState(isOpen: isOpen, reason: isOpen ? "open" : "not open")

            // Update emitter position to palm center (screen coords)
            print("[Vision] Emission point (normalized):", palmCenter)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let pt = self.previewView.previewLayer.layerPointConverted(fromCaptureDevicePoint: palmCenter)
                self.overlayView.updateEmissionPoint(pt)
            }

        } catch {
            print("[Vision][ERR] extract points failed: \(error)")
            updateOpenPalmState(isOpen: false, reason: "extract error")
        }
    }

    private func updateOpenPalmState(isOpen: Bool, reason: String) {
        if isOpen {
            openPalmStableCounter += 1
            closedStableCounter = 0
            if openPalmStableCounter == 1 {
                print("[Detector] open candidate (\(reason)) - counter = 1")
            } else {
                print("[Detector] open candidate (\(reason)) - counter = \(openPalmStableCounter)")
            }
            if openPalmStableCounter >= stableThreshold {
                DispatchQueue.main.async { [weak self] in
                    self?.overlayView.setEmitting(true)
                }
            }
        } else {
            closedStableCounter += 1
            openPalmStableCounter = 0
            if closedStableCounter == 1 {
                print("[Detector] closed/other (\(reason)) - counter = 1")
            } else {
                print("[Detector] closed/other (\(reason)) - counter = \(closedStableCounter)")
            }
            if closedStableCounter >= stableThreshold {
                DispatchQueue.main.async { [weak self] in
                    self?.overlayView.setEmitting(false)
                }
            }
        }
    }

    private func average(_ pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        let n = CGFloat(pts.count)
        return CGPoint(x: x / n, y: y / n)
    }
}

// MARK: - Preview layer host (renamed to avoid conflicts)

final class CameraPreviewView2: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Camera preview"
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isAccessibilityElement = true
        accessibilityLabel = "Camera preview"
    }
}

// MARK: - Bubble Emitter Overlay

final class BubbleEmitterView: UIView {

    private let emitterLayer = CAEmitterLayer()
    private var isEmitting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupEmitter()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEmitter()
    }

    func start() {
        print("[Overlay] start()")
        emitterLayer.birthRate = isEmitting ? 1.0 : 0.0
    }

    func stop() {
        print("[Overlay] stop()")
        emitterLayer.birthRate = 0.0
    }

    func setEmitting(_ on: Bool) {
        guard on != isEmitting else { return }
        isEmitting = on
        print("[Overlay] setEmitting: \(on)")
        emitterLayer.birthRate = on ? 1.0 : 0.0
    }

    func updateEmissionPoint(_ p: CGPoint) {
        emitterLayer.emitterPosition = p
    }

    private func setupEmitter() {
        print("[Overlay] setupEmitter()")
        emitterLayer.emitterShape = .point
        emitterLayer.emitterMode = .points
        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitterLayer.renderMode = .additive
        layer.addSublayer(emitterLayer)

        // Cells
        let cell = CAEmitterCell()
        cell.name = "bubble"
        cell.birthRate = 35
        cell.lifetime = 2.8
        cell.lifetimeRange = 0.6
        cell.velocity = 120
        cell.velocityRange = 60
        cell.scale = 0.06
        cell.scaleRange = 0.04
        cell.spin = 1.2
        cell.spinRange = 1.0
        cell.alphaSpeed = -0.4
        cell.emissionRange = .pi * 2

        // Content (circle gradient)
        cell.contents = makeBubbleImage()?.cgImage

        // Subtle color variation
        cell.color = UIColor(white: 1.0, alpha: 1.0).cgColor
        cell.redRange = 0.2
        cell.greenRange = 0.2
        cell.blueRange = 0.2

        emitterLayer.emitterCells = [cell]

        // Start off
        emitterLayer.birthRate = 0.0
    }

    private func makeBubbleImage() -> UIImage? {
        let size = CGSize(width: 80, height: 80)
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) * 0.48

            // Outer glow
            let outer = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            UIColor.white.withAlphaComponent(0.25).setFill()
            outer.fill()

            // Inner gradient-ish rings
            let colors: [UIColor] = [
                UIColor.white.withAlphaComponent(0.8),
                UIColor.white.withAlphaComponent(0.2)
            ]
            ctx.cgContext.saveGState()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map { $0.cgColor } as CFArray,
                locations: [0.0, 1.0]
            )
            ctx.cgContext.addEllipse(in: CGRect(x: center.x - radius * 0.9, y: center.y - radius * 0.9, width: radius * 1.8, height: radius * 1.8))
            ctx.cgContext.clip()
            if let gradient {
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: radius,
                    options: [.drawsAfterEndLocation]
                )
            }
            ctx.cgContext.restoreGState()

            // Specular highlight
            let highlight = UIBezierPath(ovalIn: CGRect(x: center.x - radius * 0.5, y: center.y - radius * 0.8, width: radius * 0.9, height: radius * 0.6))
            UIColor.white.withAlphaComponent(0.9).setFill()
            highlight.fill()
        }
        return img
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer.frame = bounds
    }
}

// MARK: - Debug HUD (optional, unused here but handy)

final class DebugHUD: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        numberOfLines = 2
        layer.cornerRadius = 8
        layer.masksToBounds = true
        textAlignment = .left
        print("[HUD] init")
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        print("[HUD] init(coder:)")
    }
}
