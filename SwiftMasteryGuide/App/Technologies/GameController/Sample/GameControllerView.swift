//
//  GameControllerView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 19/08/25.
//

import SwiftUI
import GameController

struct GameControllerView: View {
    @State private var controllers: [GCController] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("Game Controllers")
            BodyText("This screen lists HID game controllers detected by iOS.")

            Subtitle("Game Controllers (HID)")
            if controllers.isEmpty {
                BodyText("No controllers detected via GameController. If your controller is connected in Settings but not listed here, it is likely using a keyboard/iCade mode.")
            } else {
                List {
                    Section {
                        ForEach(controllers.indices, id: \.self) { idx in
                            ControllerRow(controller: controllers[idx])
                        }
                    }
                }
                .transaction { t in
                    t.disablesAnimations = true
                }
            }

            Button("Refresh Controllers") {
                refreshControllers()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dividerColor, lineWidth: 1)
            )
            .accessibilityLabel("Refresh game controllers")
        }
        .padding(20)
        .navigationTitle("Controllers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            GCController.shouldMonitorBackgroundEvents = true
            GCController.stopWirelessControllerDiscovery()
            GCController.startWirelessControllerDiscovery { }
            refreshControllers()

            NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { _ in
                refreshControllers()
            }
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { _ in
                refreshControllers()
            }
        }
        .onDisappear {
            GCController.stopWirelessControllerDiscovery()
        }
    }

    private func refreshControllers() {
        controllers = GCController.controllers()
    }
}

private struct ControllerRow: View {
    let controller: GCController

    var body: some View {
        let title: String = {
            if let name = controller.vendorName, !name.isEmpty {
                return name
            }
            if !controller.productCategory.isEmpty {
                return controller.productCategory
            }
            return "Game Controller"
        }()

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .accessibilityLabel("Controller \(title)")

                let attachText: String = controller.isAttachedToDevice
                ? "Attached to device"
                : "Wireless"

                Text(attachText)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            NavigationLink(
                destination: GameControllerDemoView()
            ) {
                Text("Open Demo")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Open game controller demo")
        }
        .padding(.vertical, 4)
    }
}
