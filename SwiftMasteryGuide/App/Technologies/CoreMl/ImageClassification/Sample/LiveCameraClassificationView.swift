//
//  LiveCameraClassificationView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

import SwiftUI
import AVFoundation

struct LiveCameraClassificationView: View {
    @StateObject private var viewModel = LiveCameraViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()
                .accessibilityLabel("Camera preview")

            VStack(spacing: 12) {
                Text(viewModel.resultText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .padding()
                    .background(Color.cardBackground.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Classification result")

                HStack(spacing: 12) {
                    Button("Start") { viewModel.start() }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Start camera")

                    Button("Stop") { viewModel.stop() }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dividerColor, lineWidth: 1)
                        )
                        .accessibilityLabel("Stop camera")
                }
            }
            .padding(20)
        }
        .navigationTitle("Live Classification")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
