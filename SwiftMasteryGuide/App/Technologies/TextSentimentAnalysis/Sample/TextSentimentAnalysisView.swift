//
//  TextSentimentAnalysisView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 14/08/25.
//

import SwiftUI

/// Minimal, accessible demo screen for live sentiment classification.
struct TextSentimentAnalysisView: View {
    @StateObject private var viewModel = TextSentimentAnalysisViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Title("Live Text Sentiment")

            BodyText("Type any sentence and see the predicted sentiment in real time.")

            VStack(alignment: .leading, spacing: 8) {
                Subtitle("Your text")
                TextEditor(text: $viewModel.inputText)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color.inputBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
                    .accessibilityLabel("Input text for sentiment analysis")
            }

            VStack(alignment: .leading, spacing: 8) {
                Subtitle("Prediction")
                Text(viewModel.resultSummary)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .padding()
                    .background(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Sentiment result")
            }

            Button {
                viewModel.classifyNow()
            } label: {
                Text("Classify Now")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Classify text now")

            Spacer(minLength: 12)
        }
        .padding(20)
        .navigationTitle("Text Sentiment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.inputText.isEmpty {
                viewModel.inputText = "I love how easy this app makes learning iOS."
            }
        }
    }
}
