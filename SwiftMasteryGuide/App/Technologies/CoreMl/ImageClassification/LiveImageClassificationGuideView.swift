//
//  LiveImageClassificationGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import SwiftUI
import AVFoundation
import Vision
import CoreML

/// A SwiftUI screen that explains (step-by-step) how to build
/// a live image classification demo using AVFoundation + Vision + Core ML.
struct LiveImageClassificationGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                NavigationLink(destination: LiveCameraClassificationView()) {
                    Text("Open Live Classification Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open live classification demo")

                Title("Live Image Classification (Camera) – Core ML + Vision")

                Subtitle("What you’ll build")
                BodyText("""
                A camera preview that runs continuous inference (with throttling) using a Core ML model via Vision, showing the top predicted label and confidence.
                """)

                Subtitle("Requirements")
                BulletList([
                    "iOS 15+.",
                    "Camera permission (NSCameraUsageDescription in Info.plist).",
                    "Add a .mlmodel to the project (e.g., MobileNetV2FP16).",
                    "Frameworks: AVFoundation, Vision, CoreML."
                ])

                DividerLine()

                Subtitle("Architecture")
                BodyText("""
                • CameraManager → configures AVCaptureSession and delivers frames as CVPixelBuffer.
                • LiveImageClassifier → wraps VNCoreMLRequest, handles orientation, and applies a minimum confidence threshold.
                • LiveCameraViewModel → wires frames into the classifier, does temporal smoothing, and publishes UI text.
                • LiveCameraClassificationView → SwiftUI screen that renders the preview and displays results.
                """)

                Subtitle("1) CameraManager")
                BodyText("Configures capture session, forwards frames, and sets portrait rotation using the iOS 17+ API with a fallback. Stop() really stops: removes delegate, I/O and callback.")
                CodeBlock("""
                import AVFoundation
                import UIKit
                
                final class CameraManager: NSObject {
                    let session = AVCaptureSession()
                    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
                    private let videoDataOutput = AVCaptureVideoDataOutput()
                
                    /// Callback invoked for each captured CVPixelBuffer frame.
                    var onFrame: ((CVPixelBuffer) -> Void)?
                
                    func start() {
                        sessionQueue.async {
                            if !self.session.isRunning {
                                self.configureIfNeeded()
                                self.session.startRunning()
                            }
                        }
                    }
                
                    func stop() {
                        sessionQueue.async {
                            // Stop capture if running OR if we had configured once.
                            guard self.session.isRunning || self.isConfigured else { return }
                
                            // 1) Stop session
                            self.session.stopRunning()
                
                            // 2) Remove delegate to break any reference chain
                            self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
                
                            // 3) Remove outputs/inputs to release resources
                            self.session.beginConfiguration()
                            self.session.outputs.forEach { self.session.removeOutput($0) }
                            self.session.inputs.forEach { self.session.removeInput($0) }
                            self.session.commitConfiguration()
                
                            // 4) Release callback
                            self.onFrame = nil
                
                            // 5) Allow reconfiguration on next start()
                            self.isConfigured = false
                        }
                    }
                
                    private var isConfigured = false
                    private func configureIfNeeded() {
                        guard !isConfigured else { return }
                
                        session.beginConfiguration()
                        session.sessionPreset = .vga640x480 // switch to .hd1280x720 if objects are small
                
                        // Input (back camera)
                        guard
                            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                            let input = try? AVCaptureDeviceInput(device: device),
                            session.canAddInput(input)
                        else {
                            session.commitConfiguration()
                            return
                        }
                        session.addInput(input)
                
                        // Output
                        videoDataOutput.alwaysDiscardsLateVideoFrames = true
                        videoDataOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                        ]
                        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                        guard session.canAddOutput(videoDataOutput) else {
                            session.commitConfiguration()
                            return
                        }
                        session.addOutput(videoDataOutput)
                
                        // Orientation: portrait (iOS 17+ angle; fallback pre‑iOS 17)
                        if let connection = videoDataOutput.connection(with: .video) {
                            if #available(iOS 17, *) {
                                if connection.isVideoRotationAngleSupported(90) { // 90° = portrait
                                    connection.videoRotationAngle = 90
                                }
                            } else {
                                if connection.isVideoOrientationSupported {
                                    connection.videoOrientation = .portrait
                                }
                            }
                        }
                
                        isConfigured = true
                        session.commitConfiguration()
                    }
                }
                
                extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
                    func captureOutput(
                        _ output: AVCaptureOutput,
                        didOutput sampleBuffer: CMSampleBuffer,
                        from connection: AVCaptureConnection
                    ) {
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                        onFrame?(pixelBuffer)
                    }
                }
                """)

                Subtitle("2) LiveImageClassifier")
                BodyText("Wraps the Core ML model in a VNCoreMLRequest, passes the correct orientation to Vision, filters low-confidence guesses, and supports cancellation. Uses weak self inside the queue.")
                CodeBlock("""
                import Vision
                import CoreML
                import CoreVideo
                import ImageIO
                import UIKit
                
                final class LiveImageClassifier {
                
                    private let visionModel: VNCoreMLModel
                    private let classificationQueue = DispatchQueue(label: "coreml.imageclassification.queue")
                    private let minimumConfidence: Float = 0.20  // ignore very low-confidence guesses
                    private var isCancelled = false
                
                    init() throws {
                        let modelConfiguration = MLModelConfiguration()
                        modelConfiguration.computeUnits = .all
                        // Uses the auto-generated class from your MobileNetV2FP16.mlmodel
                        let coreMLModel = try MobileNetV2FP16(configuration: modelConfiguration).model
                        let visionCoreMLModel = try VNCoreMLModel(for: coreMLModel)
                        visionCoreMLModel.inputImageFeatureName = "image" // safe even if already correct
                        visionModel = visionCoreMLModel
                    }
                
                    func cancel() { isCancelled = true }
                
                    func classify(
                        pixelBuffer: CVPixelBuffer,
                        completion: @escaping (_ label: String, _ confidence: Float) -> Void
                    ) {
                        classificationQueue.async { [weak self] in
                            guard let self, !self.isCancelled else { return }
                
                            let request = VNCoreMLRequest(model: self.visionModel) { request, _ in
                                guard let best = (request.results as? [VNClassificationObservation])?.first else { return }
                                guard best.confidence >= self.minimumConfidence else { return }
                                completion(best.identifier, best.confidence)
                            }
                            request.imageCropAndScaleOption = .centerCrop
                
                            let orientation = Self.currentCGImageOrientation()
                            let handler = VNImageRequestHandler(
                                cvPixelBuffer: pixelBuffer,
                                orientation: orientation,
                                options: [:]
                            )
                            do {
                                try handler.perform([request])
                            } catch {
                                // Optionally log the classification error
                            }
                        }
                    }
                
                    private static func currentCGImageOrientation() -> CGImagePropertyOrientation {
                        // Mapping assumes back camera. If you add front camera, revisit mirroring.
                        switch UIDevice.current.orientation {
                        case .landscapeLeft:  return .upMirrored
                        case .landscapeRight: return .down
                        case .portraitUpsideDown: return .left
                        default: return .right // portrait
                        }
                    }
                }
                """)

                Subtitle("3) Camera preview (SwiftUI)")
                BodyText("A wrapper to host AVCaptureVideoPreviewLayer inside SwiftUI.")
                CodeBlock("""
                import SwiftUI
                import AVFoundation
                
                struct CameraPreviewView: UIViewRepresentable {
                    let session: AVCaptureSession
                
                    func makeUIView(context: Context) -> PreviewView {
                        let previewView = PreviewView()
                        previewView.videoPreviewLayer.session = session
                        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
                        return previewView
                    }
                
                    func updateUIView(_ uiView: PreviewView, context: Context) {
                        // No-op
                    }
                
                    final class PreviewView: UIView {
                        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
                        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
                            return layer as! AVCaptureVideoPreviewLayer
                        }
                
                        override var accessibilityLabel: String? {
                            get { "Camera preview" }
                            set { /* keep consistent */ }
                        }
                
                        override var isAccessibilityElement: Bool {
                            get { true }
                            set { /* keep true */ }
                        }
                    }
                }
                """)

                Subtitle("4) ViewModel")
                BodyText("Wires camera frames into the classifier, applies temporal smoothing, publishes display strings, and stops everything cleanly.")
                CodeBlock("""
                import SwiftUI
                import AVFoundation
                
                final class LiveCameraViewModel: ObservableObject {
                    @Published var topLabel: String = "—"
                    @Published var confidenceText: String = "—"
                
                    var resultText: String { "\\(topLabel)  •  \\(confidenceText)" }
                
                    let camera = CameraManager()
                    private var classifier: LiveImageClassifier?
                    private var lastInferenceTimeSeconds = CFAbsoluteTimeGetCurrent()
                    private let temporalSmoother = TemporalSmoother()
                    private var isActive = false
                
                    init() {
                        camera.onFrame = { [weak self] pixelBuffer in
                            self?.processFrame(pixelBuffer)
                        }
                        do {
                            classifier = try LiveImageClassifier()
                        } catch {
                            topLabel = "Model load failed"
                            confidenceText = ""
                        }
                    }
                
                    func start() {
                        isActive = true
                        camera.start()
                    }
                
                    func stop() {
                        isActive = false
                        camera.stop()
                        classifier?.cancel()
                        classifier = nil
                    }
                
                    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
                        guard isActive else { return } // avoid work after leaving the screen
                
                        // ~10 FPS throttle to reduce battery
                        let now = CFAbsoluteTimeGetCurrent()
                        guard now - lastInferenceTimeSeconds > 0.1 else { return }
                        lastInferenceTimeSeconds = now
                
                        guard let classifier else { return }
                        classifier.classify(pixelBuffer: pixelBuffer) { [weak self] label, confidence in
                            guard let self, self.isActive else { return }
                            let smoothed = self.temporalSmoother.update(label: label, confidence: confidence)
                            DispatchQueue.main.async {
                                guard self.isActive else { return }
                                self.topLabel = smoothed.label
                                self.confidenceText = String(format: "%.0f%%", smoothed.confidence * 100)
                            }
                        }
                    }
                }
                
                /// Simple temporal smoothing: EMA for confidence + brief label lock for stability.
                final class TemporalSmoother {
                    private var lastStableLabel: String?
                    private var stableFrameCount = 0
                    private var exponentialMovingAverage: Float = 0
                    private let alpha: Float = 0.30
                    private let framesRequiredForLock = 3
                
                    func update(label: String, confidence: Float) -> (label: String, confidence: Float) {
                        exponentialMovingAverage = exponentialMovingAverage == 0
                            ? confidence
                            : (alpha * confidence + (1 - alpha) * exponentialMovingAverage)
                
                        if label == lastStableLabel {
                            stableFrameCount += 1
                        } else {
                            lastStableLabel = label
                            stableFrameCount = 1
                        }
                        let lockedLabel = (stableFrameCount >= framesRequiredForLock) ? label : (lastStableLabel ?? label)
                        return (lockedLabel, exponentialMovingAverage)
                    }
                }
                """)

                Subtitle("5) Live demo screen (SwiftUI)")
                BodyText("Shows the camera preview and a result card. Accessible and responsive.")
                CodeBlock("""
                import SwiftUI
                
                struct LiveCameraClassificationView: View {
                    @StateObject private var viewModel = LiveCameraViewModel()
                
                    var body: some View {
                        ZStack(alignment: .bottom) {
                            CameraPreviewView(session: viewModel.camera.session)
                                .ignoresSafeArea()
                                .accessibilityLabel("Camera preview")
                
                            VStack(spacing: 12) {
                                Text(viewModel.resultText)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .padding()
                                    .background(Color.cardBackground.opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.dividerColor, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Classification result")
                
                                HStack(spacing: 12) {
                                    Button("Start") { viewModel.start() }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityLabel("Start camera")
                
                                    Button("Stop") { viewModel.stop() }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.dividerColor, lineWidth: 1)
                                        )
                                        .accessibilityLabel("Stop camera")
                                }
                            }
                            .padding(20)
                        }
                        .navigationTitle("Live Classification")
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear { viewModel.start() }
                        .onDisappear { viewModel.stop() }
                    }
                }
                """)

                DividerLine()

                Subtitle("Permissions & Tips")
                BulletList([
                    "Add NSCameraUsageDescription in Info.plist (e.g., “This app needs camera access to classify objects in real time”).",
                    "Keep a minimum interval between inferences (e.g., 150 ms) to balance performance and battery.",
                    "Use .centerCrop for classification models to keep predictions stable.",
                    "If objects are small, switch preset to .hd1280x720 for more pixels (trade-off: battery/CPU).",
                    "For the best results, make the object fill ~40–60% of the frame and keep it centered under good lighting."
                ])

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
