//
//  CoreMLFeaturesListView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import SwiftUI

struct CoreMLFeaturesListView: View {
    private enum CoreMLFeature: String, CaseIterable, Identifiable {
        case imageClassification = "ImageClassification"
        case objectDetection = "ObjectDetection"
        case imageSegmentation = "ImageSegmentation"
        case faceAndExpressionRecognition = "FaceAndExpressionRecognition"
        case textRecognition = "TextRecognition" // OCR
        case speechToText = "SpeechToText"
        case soundClassification = "SoundClassification"
        case speechSentimentAnalysis = "SpeechSentimentAnalysis"
        case textSentimentAnalysis = "TextSentimentAnalysis"
        case machineTranslation = "MachineTranslation"
        case augmentedRealityFilters = "AugmentedRealityFilters"
        case onDeviceAssistants = "OnDeviceAssistants"

        var id: String { rawValue }
    }

    private let items = CoreMLFeature.allCases.sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        NavigationView {
            List(items) { feature in
                NavigationLink(destination: destination(for: feature)) {
                    Text(feature.rawValue)
                }
                .accessibilityLabel("Open guide for \(feature.rawValue)")
            }
            .navigationTitle("Core ML Features")
        }
    }

    // MARK: - Navigation mapping
    @ViewBuilder
    private func destination(for feature: CoreMLFeature) -> some View {
        switch feature {
            case .imageClassification:
                LiveImageClassificationGuideView()

            case .objectDetection:
                ComingSoonView(featureName: feature.rawValue)

            case .imageSegmentation:
                ComingSoonView(featureName: feature.rawValue)

            case .faceAndExpressionRecognition:
                ComingSoonView(featureName: feature.rawValue)

            case .textRecognition:
                ComingSoonView(featureName: feature.rawValue)

            case .speechToText:
                ComingSoonView(featureName: feature.rawValue)

            case .soundClassification:
                ComingSoonView(featureName: feature.rawValue)

            case .speechSentimentAnalysis:
                ComingSoonView(featureName: feature.rawValue)

            case .textSentimentAnalysis:
                ComingSoonView(featureName: feature.rawValue)

            case .machineTranslation:
                ComingSoonView(featureName: feature.rawValue)

            case .augmentedRealityFilters:
                ComingSoonView(featureName: feature.rawValue)

            case .onDeviceAssistants:
                ComingSoonView(featureName: feature.rawValue)
        }
    }
}

// Simple placeholder to avoid build errors until each guide is implemented.
private struct ComingSoonView: View {
    let featureName: String
    var body: some View {
        VStack(spacing: 16) {
            Title(featureName)
            BodyText("This guide is coming soon. Stay tuned!")
        }
        .padding(20)
        .navigationTitle(featureName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
