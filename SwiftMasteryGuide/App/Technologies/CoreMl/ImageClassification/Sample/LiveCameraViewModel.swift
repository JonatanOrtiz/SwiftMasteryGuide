//
//  LiveCameraViewModel.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//


import SwiftUI
import AVFoundation

final class LiveCameraViewModel: ObservableObject {
    @Published var topLabel: String = "—"
    @Published var confidenceText: String = "—"

    var resultText: String { "\(topLabel)  •  \(confidenceText)" }

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
        guard isActive else { return } // evita processar após sair

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

