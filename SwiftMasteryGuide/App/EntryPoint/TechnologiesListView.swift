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
        var id: String { rawValue }
    }

    private let items = Technology.allCases.sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        NavigationView {
            List(items) { tech in
                NavigationLink(destination: CoreHapticsGuideView()) {
                    Text(tech.rawValue)
                }
            }
            .navigationTitle("Swift Mastery Guide")
        }
    }
}
