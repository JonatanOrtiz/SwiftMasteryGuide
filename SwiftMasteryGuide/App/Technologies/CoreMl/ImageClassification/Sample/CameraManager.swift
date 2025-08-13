//
//  CameraManager.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

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
            guard self.session.isRunning || !self.isConfigured else { return }

            self.session.stopRunning()

            self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)

            self.session.beginConfiguration()
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.commitConfiguration()

            self.onFrame = nil

            self.isConfigured = false
        }
    }

    private var isConfigured = false
    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

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

        if let connection = videoDataOutput.connection(with: .video) {
            if #available(iOS 17, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
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
