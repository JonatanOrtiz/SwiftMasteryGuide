//
//  CoreMLFeaturesListView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import SwiftUI

struct CoreMLFeaturesListView: View {
    private enum CoreMLFeature: String, CaseIterable, Identifiable {
        case imageClassification = "Image Classification"
        case speechToText = "Speech To Text"

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
            case .speechToText:
                SpeechToTextGuideView()
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
