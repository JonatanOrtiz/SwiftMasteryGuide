//
//  TextSentimentAnalysisViewModel.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 14/08/25.
//

import Foundation
import Combine

/// Handles debounced input, calls the analyzer, and publishes UI state.
final class TextSentimentAnalysisViewModel: ObservableObject {

    // MARK: - Published UI state

    @Published var inputText: String = "" {
        didSet { scheduleClassification() }
    }

    @Published var resultLabel: String = "—"
    @Published var confidenceText: String = "—"

    /// Convenience for the card.
    var resultSummary: String {
        "\(resultLabel)  •  \(confidenceText)"
    }

    // MARK: - Private

    private let analyzer: TextSentimentAnalyzer?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.25

    init(analyzer: TextSentimentAnalyzer? = TextSentimentAnalyzer()) {
        self.analyzer = analyzer
    }

    /// Forces immediate classification (used by the button).
    func classifyNow() {
        let current = inputText
        runClassification(for: current)
    }

    private func scheduleClassification() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.runClassification(for: self.inputText)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func runClassification(for text: String) {
        guard let analyzer = analyzer else {
            resultLabel = "Model not available"
            confidenceText = ""
            return
        }
        analyzer.classify(text: text) { [weak self] label, conf in
            guard let self = self else { return }
            self.resultLabel = label.capitalized
            self.confidenceText = String(format: "%.0f%%", conf * 100)
        }
    }
}
