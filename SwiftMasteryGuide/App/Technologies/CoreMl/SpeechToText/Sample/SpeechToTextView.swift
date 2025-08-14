//
//  SpeechToTextView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 13/08/25.
//

import SwiftUI

struct SpeechToTextView: View {
    @StateObject private var viewModel = SpeechToTextViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("Speech-to-Text with Core ML")
            BodyText("This example uses Whisper via Core ML to transcribe your speech in real time.")

            DividerLine()

            Subtitle("Live Transcription")
            ScrollView {
                Text(viewModel.transcription)
                    .font(.system(size: 16))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.backgroundSurface)
                    .cornerRadius(10)
            }

            Button(action: {
                viewModel.toggleRecording()
            }) {
                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .accessibilityLabel(viewModel.isRecording ? "Stop Recording" : "Start Recording")
        }
        .padding(20)
        .onAppear { viewModel.requestPermissions() }
    }
}
