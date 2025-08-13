//
//  CameraPreviewView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import SwiftUI
import AVFoundation

/// SwiftUI wrapper around AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let previewView = PreviewView()
        previewView.videoPreviewLayer.session = session
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        return previewView
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // No-op: session and gravity are already set.
        // If you need to react to state changes, do it here.
    }

    /// Backed by AVCaptureVideoPreviewLayer to render camera frames efficiently.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        // Optional: better readability for VoiceOver users.
        override var accessibilityLabel: String? {
            get { "Camera preview" }
            set { /* ignore external set to keep label consistent */ }
        }

        override var isAccessibilityElement: Bool {
            get { true }
            set { /* keep true */ }
        }
    }
}
