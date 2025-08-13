//
//  LiveImageClassifier.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import Vision
import CoreML
import CoreVideo
import ImageIO
import UIKit

/// Wraps a Core ML image classifier for live camera frames.
final class LiveImageClassifier {

    private let visionModel: VNCoreMLModel
    private let classificationQueue = DispatchQueue(label: "coreml.imageclassification.queue")
    private let minimumConfidence: Float = 0.20
    private var isCancelled = false

    init() throws {
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = .all
        let coreMLModel = try MobileNetV2FP16(configuration: modelConfiguration).model
        let visionCoreMLModel = try VNCoreMLModel(for: coreMLModel)
        visionCoreMLModel.inputImageFeatureName = "image"
        visionModel = visionCoreMLModel
    }

    func cancel() {
        isCancelled = true
    }

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
                // log se quiser
            }
        }
    }

    private static func currentCGImageOrientation() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
            case .landscapeLeft:  return .upMirrored
            case .landscapeRight: return .down
            case .portraitUpsideDown: return .left
            default: return .right // portrait
        }
    }
}
