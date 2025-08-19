//
//  BluetoothScannerView.swift.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import SwiftUI

struct BluetoothScannerView: View {
    @StateObject private var vm = BluetoothScannerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("BLE Device Scanner")
            BodyText(
                "Scan for nearby BLE devices and inspect their services in a detail view."
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

            ControlsBar(
                onStartScan: { vm.startScanning() },
                onStopScan: { vm.stopScanning() }
            )
        }
        .padding(20)
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
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

private struct ControlsBar: View {
    let onStartScan: () -> Void
    let onStopScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Start Scan") {
                onStartScan()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Start Bluetooth scan")

            Button("Stop Scan") {
                onStopScan()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dividerColor, lineWidth: 1)
            )
            .accessibilityLabel("Stop Bluetooth scan")
        }
    }
}
