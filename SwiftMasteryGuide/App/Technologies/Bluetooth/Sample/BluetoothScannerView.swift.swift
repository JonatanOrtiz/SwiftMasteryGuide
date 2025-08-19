//
//  BluetoothScannerView.swift.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import SwiftUI
import GameController

struct BluetoothScannerView: View {
    @StateObject private var vm = BluetoothScannerViewModel()

    // HID (GameController) section state
    @State private var controllers: [GCController] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("BLE Device Scanner")
            BodyText(
                "Scan for nearby BLE devices and inspect their services in a detail view. This screen also lists HID game controllers detected by iOS."
            )

            Text(vm.stateText)
                .foregroundColor(.textSecondary)
                .accessibilityLabel(
                    "Bluetooth state \(vm.stateText)"
                )

            Toggle(
                isOn: $vm.sortBySignal
            ) {
                Text("Sort by signal (throttled)")
                    .font(.system(size: 14))
            }
            .padding(.trailing, 8)
            .accessibilityLabel(
                "Sort devices by signal strength"
            )

            DividerLine()

            Subtitle("BLE Devices")

            BLEDevicesSection(
                items: vm.items,
                viewModelProvider: { vm }
            )
            .transaction { t in
                t.disablesAnimations = true
            }

            DividerLine()

            Subtitle("Game Controllers (HID)")

            ControllersSection(
                controllers: controllers
            )

            ControlsBar(
                onStartScan: { vm.startScanning() },
                onStopScan: { vm.stopScanning() },
                onRefreshControllers: { refreshControllers() }
            )
        }
        .padding(20)
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            GCController.shouldMonitorBackgroundEvents = true
            GCController.stopWirelessControllerDiscovery()
            GCController.startWirelessControllerDiscovery { }
            refreshControllers()
        }
        .onDisappear {
            GCController.stopWirelessControllerDiscovery()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .GCControllerDidConnect
            )
        ) { _ in
            refreshControllers()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .GCControllerDidDisconnect
            )
        ) { _ in
            refreshControllers()
        }
    }

    // MARK: - Helpers

    private func refreshControllers() {
        let all: [GCController] = GCController.controllers()
        controllers = all
    }
}

// MARK: - Subviews

private struct BLEDevicesSection: View {
    let items: [DiscoveredPeripheral]
    let viewModelProvider: () -> BluetoothScannerViewModel

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink(
                        destination:
                            PeripheralDetailView(
                                peripheralId: item.id,
                                viewModelProvider: { viewModelProvider() }
                            )
                    ) {
                        BLEDeviceRow(item: item)
                    }
                }
            }
        }
    }
}

private struct BLEDeviceRow: View {
    let item: DiscoveredPeripheral

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .accessibilityLabel(
                        "Device \(item.name)"
                    )

                // Human-friendly preview of up to 3 advertised services (if any).
                let servicesPreview: String = item.advertisedServices
                    .prefix(3)
                    .map { BLEKnownServices.friendlyName(for: $0) }
                    .joined(separator: ", ")

                if !servicesPreview.isEmpty {
                    Text(servicesPreview)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                } else {
                    // Neutral: do not speculate HID/keyboard/controller/etc.
                    Text("No advertised services")
                        .font(.system(size: 14))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(item.rssi) dBm")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .accessibilityLabel(
                        "Signal \(item.rssi) dBm"
                    )

                // Neutral evidence-based tag:
                // - If we saw at least one service UUID in the advertisement → show a small counter.
                // - Else → say “Advertisement only”.
                let servicesCount: Int = item.advertisedServices.count
                if servicesCount > 0 {
                    Label(
                        "Services in ad: \(servicesCount)",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel(
                        "Services in advertisement \(servicesCount)"
                    )
                } else {
                    Label(
                        "Advertisement only",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel(
                        "Advertisement only"
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ControllersSection: View {
    let controllers: [GCController]

    var body: some View {
        if controllers.isEmpty {
            BodyText(
                "No controllers detected via GameController. If your controller is connected in Settings but not listed here, it may be using a profile that the GameController framework does not enumerate."
            )
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
    }
}

private struct ControllerRow: View {
    let controller: GCController

    var body: some View {
        // Resolve a non‑optional title first to help the type checker.
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
                    .accessibilityLabel(
                        "Controller \(title)"
                    )

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
            .accessibilityLabel(
                "Open game controller demo"
            )
        }
        .padding(.vertical, 4)
    }
}

private struct ControlsBar: View {
    let onStartScan: () -> Void
    let onStopScan: () -> Void
    let onRefreshControllers: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(
                "Start Scan"
            ) {
                onStartScan()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(
                "Start Bluetooth scan"
            )

            Button(
                "Stop Scan"
            ) {
                onStopScan()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dividerColor, lineWidth: 1)
            )
            .accessibilityLabel(
                "Stop Bluetooth scan"
            )

            Button(
                "Refresh Controllers"
            ) {
                onRefreshControllers()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dividerColor, lineWidth: 1)
            )
            .accessibilityLabel(
                "Refresh game controllers"
            )
        }
    }
}
