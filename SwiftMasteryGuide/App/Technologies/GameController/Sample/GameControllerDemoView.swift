//
//  GameControllerDemoView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import SwiftUI
import GameController

struct GameControllerDemoView: View {
    @StateObject private var manager = GameControllerInputManager()

    private func boolBadge(_ title: String, _ on: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(on ? Color.success.opacity(0.9) : Color.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.dividerColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(title) \(on ? "pressed" : "not pressed")")
    }

    private func axisRow(_ name: String, _ x: Float, _ y: Float) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 12) {
                ProgressView(value: Double((x + 1) / 2))
                    .accessibilityLabel("\(name) X axis \(x)")
                Text(String(format: "x: %.2f", x))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                ProgressView(value: Double((y + 1) / 2))
                    .accessibilityLabel("\(name) Y axis \(y)")
                Text(String(format: "y: %.2f", y))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func triggerRow(_ name: String, _ v: Float) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.system(size: 14, weight: .semibold))
            ProgressView(value: Double(v))
                .accessibilityLabel("\(name) \(v)")
            Text(String(format: "%.2f", v))
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Title("Game Controller (HID) – Live Input")

                BodyText("""
                If your controller is paired in Settings and shows as Connected, use this screen to read inputs via the GameController framework.
                """)

                HStack(spacing: 12) {
                    Button("Refresh Controllers") {
                        GCController.stopWirelessControllerDiscovery()
                        manager.discoverControllers()
                        manager.attachToFirstAvailableController()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
                    .accessibilityLabel("Refresh controllers")
                }

                DividerLine()

                Subtitle("Connection")
                BodyText("Status: \(manager.isControllerConnected ? "Connected" : "Not Connected")")
                BodyText("Name: \(manager.snapshot.name)")
                if let vn = manager.snapshot.vendorName {
                    BodyText("Vendor: \(vn)")
                }

                DividerLine()

                Subtitle("Buttons")
                HStack(spacing: 8) {
                    boolBadge("A", manager.snapshot.buttonSouthPressed)
                    boolBadge("B", manager.snapshot.buttonEastPressed)
                    boolBadge("X", manager.snapshot.buttonWestPressed)
                    boolBadge("Y", manager.snapshot.buttonNorthPressed)
                    boolBadge("Menu", manager.snapshot.menuPressed)
                }

                HStack(spacing: 8) {
                    boolBadge("L1", manager.snapshot.leftShoulderPressed)
                    boolBadge("R1", manager.snapshot.rightShoulderPressed)
                }

                DividerLine()

                Subtitle("D‑Pad")
                axisRow("D‑Pad", manager.snapshot.dpadX, manager.snapshot.dpadY)

                DividerLine()

                Subtitle("Thumbsticks")
                axisRow("Left Stick", manager.snapshot.leftThumbstickX, manager.snapshot.leftThumbstickY)
                axisRow("Right Stick", manager.snapshot.rightThumbstickX, manager.snapshot.rightThumbstickY)

                DividerLine()

                Subtitle("Triggers")
                triggerRow("L2", manager.snapshot.leftTrigger)
                triggerRow("R2", manager.snapshot.rightTrigger)
            }
            .padding(20)
        }
        .navigationTitle("Controller Input")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.discoverControllers()
            manager.attachToFirstAvailableController()
        }
        .onDisappear {
            GCController.stopWirelessControllerDiscovery()
        }
    }
}
