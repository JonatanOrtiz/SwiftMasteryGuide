//
//  PeripheralDetailView.swift.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import SwiftUI
import CoreBluetooth

struct PeripheralDetailView: View {
    let peripheralId: UUID
    let viewModelProvider: () -> BluetoothScannerViewModel

    @StateObject private var connector = PeripheralConnectionManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Title("Peripheral Details")

                if let meta = connector.meta {
                    BodyText("Name: \(meta.name)")
                    BodyText("Identifier: \(meta.id.uuidString)")
                    BodyText("State: \(connector.stateText)")
                    if !meta.advertisedServices.isEmpty {
                        BodyText(
                            "Advertised Services: " +
                            meta.advertisedServices
                                .map { BLEKnownServices.friendlyName(for: $0) }
                                .joined(separator: ", ")
                        )
                    } else {
                        BodyText("Advertised Services: None")
                    }
                } else {
                    BodyText("Loading peripheral…")
                }

                DividerLine()

                HStack(spacing: 12) {
                    Button("Connect") {
                        // Stop scanning before connecting to avoid contention
                        let vm = viewModelProvider()
                        vm.stopScanning()
                        connector.connectIfNeeded()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Connect to peripheral")

                    Button("Close GATT Connection") {
                        connector.disconnect()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.dividerColor, lineWidth: 1)
                    )
                    .accessibilityLabel("Close GATT session with peripheral")
                }

                DividerLine()

                Subtitle("Discovered Services")
                if connector.discoveredServices.isEmpty {
                    BodyText("—")
                } else {
                    ForEach(connector.discoveredServices, id: \.uuid) { service in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(BLEKnownServices.friendlyName(for: service.uuid))
                                .font(.system(size: 16, weight: .semibold))
                            if let chars = connector.characteristicsByService[service.uuid] {
                                ForEach(chars, id: \.uuid) { ch in
                                    HStack {
                                        Text("• \(ch.uuid.uuidString)")
                                            .font(.system(size: 14))
                                        Spacer()
                                        if ch.properties.contains(.notify) {
                                            Button(connector.isNotifying(ch) ? "Unsubscribe" : "Subscribe") {
                                                connector.toggleNotify(for: ch)
                                            }
                                            .font(.system(size: 12, weight: .semibold))
                                        }
                                        if ch.properties.contains(.read) {
                                            Button("Read") {
                                                connector.read(ch)
                                            }
                                            .font(.system(size: 12, weight: .semibold))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                DividerLine()

                Subtitle("Live Log (HEX)")
                ScrollView {
                    Text(connector.hexLog.joined(separator: "\n"))
                        .font(.system(.footnote, design: .monospaced))
                        .padding(12)
                        .background(Color.codeBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.codeBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: 240)
            }
            .padding(20)
        }
        .navigationTitle("Peripheral")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let vm = viewModelProvider()
            let cb = vm.cbPeripheral(for: peripheralId)
            connector.prepare(with: cb)
            vm.stopScanning()
        }
        .onDisappear {
            connector.teardown()
        }
    }
}
