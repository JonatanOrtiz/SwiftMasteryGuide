//
//  ContentView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct TechnologiesListView: View {
    private enum Technology: String, CaseIterable, Identifiable {
        case coreHaptics = "Core Haptics"
        case coreML = "Core ML"
        var id: String { rawValue }
    }

    private let items = Technology.allCases.sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        NavigationView {
            List(items) { tech in
                NavigationLink(destination: destination(for: tech)) {
                    Text(tech.rawValue)
                }
                .accessibilityLabel("Abrir guia de \(tech.rawValue)")
            }
            .navigationTitle("Swift Mastery Guide")
        }
    }

    @ViewBuilder
    private func destination(for tech: Technology) -> some View {
        switch tech {
            case .coreHaptics:
                CoreHapticsGuideView()
            case .coreML:
                CoreMLFeaturesListView()
        }
    }
}
