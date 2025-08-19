//
//  BluetoothGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 19/08/25.
//

import SwiftUI
import CoreBluetooth

/// A SwiftUI screen that explains step-by-step how the BLE scanner and GATT connection feature works using CoreBluetooth.
struct BluetoothGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                Title("Bluetooth Low Energy Scanner – CoreBluetooth")

                Subtitle("What you’ll build")
                BodyText("""
                A SwiftUI BLE scanner that lists nearby peripherals, identifies advertised services, allows connection to GATT, and displays live characteristics with read and notify capabilities.
                """)

                Subtitle("Requirements")
                BulletList([
                    "iOS 15+.",
                    "Bluetooth permission (NSBluetoothAlwaysUsageDescription).",
                    "Frameworks: CoreBluetooth, SwiftUI."
                ])

                DividerLine()

                Subtitle("Architecture Overview")
                BodyText("""
                • BluetoothScannerViewModel – Manages BLE scanning logic with throttled UI updates and signal smoothing.
                • PeripheralConnectionManager – Handles GATT connection, service and characteristic discovery.
                • BluetoothScannerView – Main interface for scanning and listing peripherals.
                • PeripheralDetailView – Shows details and live interactions with a selected peripheral.
                """)

                Subtitle("1) ViewModel for Scanning")
                BodyText("Handles CBCentralManager and filters/displays discovered peripherals.")
                CodeBlock("""
                // File: BluetoothScannerViewModel.swift
                final class BluetoothScannerViewModel: NSObject, ObservableObject {
                    @Published var stateText: String = "Waiting for Bluetooth…"
                    @Published var items: [DiscoveredPeripheral] = []
                    @Published var sortBySignal: Bool = false
                
                    private var central: CBCentralManager?
                    private var seen: [UUID: MutablePeripheral] = [:]
                    private var order: [UUID] = []
                    private let rssiAlpha: Double = 0.25
                
                    override init() {
                        super.init()
                        central = CBCentralManager(delegate: self, queue: nil)
                    }
                
                    func startScanning() {
                        guard let central, central.state == .poweredOn else { return }
                        central.scanForPeripherals(
                            withServices: nil,
                            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                        )
                        stateText = "Scanning…"
                    }
                
                    func stopScanning() {
                        central?.stopScan()
                        stateText = "Stopped"
                        seen.removeAll()
                        order.removeAll()
                        items = []
                    }
                }
                """)

                Subtitle("2) BLE Device Row")
                BodyText("Each device shows name, signal, and known service previews.")
                CodeBlock("""
                // File: BluetoothScannerView.swift
                private struct BLEDeviceRow: View {
                    let item: DiscoveredPeripheral
                
                    var body: some View {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.system(size: 16, weight: .semibold))
                                Text(item.advertisedServices
                                    .prefix(3)
                                    .map { BLEKnownServices.friendlyName(for: $0) }
                                    .joined(separator: ", "))
                                .font(.system(size: 14))
                            }
                
                            Spacer()
                
                            VStack(alignment: .trailing) {
                                Text("\\(item.rssi) dBm").font(.system(size: 12))
                                Label("Services: \\(item.advertisedServices.count)", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                }
                """)

                Subtitle("3) Peripheral Connection")
                BodyText("Manages connection, service/characteristic discovery and handles read/notify.")
                CodeBlock("""
                // File: PeripheralConnectionManager.swift
                final class PeripheralConnectionManager: NSObject, ObservableObject {
                    @Published var discoveredServices: [CBService] = []
                    @Published var characteristicsByService: [CBUUID : [CBCharacteristic]] = [:]
                
                    func prepare(with peripheral: CBPeripheral?) {
                        self.peripheral = peripheral
                        peripheral?.delegate = self
                        discoveredServices.removeAll()
                        characteristicsByService.removeAll()
                    }
                
                    func connectIfNeeded() {
                        guard let c = central, let p = peripheral else { return }
                        c.connect(p, options: nil)
                    }
                
                    func disconnect() {
                        guard let c = central, let p = peripheral else { return }
                        c.cancelPeripheralConnection(p)
                    }
                
                    func toggleNotify(for ch: CBCharacteristic) {
                        peripheral?.setNotifyValue(!isNotifying(ch), for: ch)
                    }
                
                    func read(_ ch: CBCharacteristic) {
                        peripheral?.readValue(for: ch)
                    }
                }
                """)

                Subtitle("4) Peripheral Detail View")
                BodyText("Provides connection controls and lists discovered services and characteristics.")
                CodeBlock("""
                // File: PeripheralDetailView.swift
                struct PeripheralDetailView: View {
                    let peripheralId: UUID
                    @StateObject private var connector = PeripheralConnectionManager()
                
                    var body: some View {
                        VStack {
                            Button("Connect") { connector.connectIfNeeded() }
                            Button("Disconnect") { connector.disconnect() }
                
                            ForEach(connector.discoveredServices, id: \\.uuid) { service in
                                Text(BLEKnownServices.friendlyName(for: service.uuid))
                                ForEach(connector.characteristicsByService[service.uuid] ?? [], id: \\.uuid) { ch in
                                    HStack {
                                        Text(ch.uuid.uuidString)
                                        if ch.properties.contains(.read) {
                                            Button("Read") { connector.read(ch) }
                                        }
                                        if ch.properties.contains(.notify) {
                                            Button("Notify") { connector.toggleNotify(for: ch) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                """)

                DividerLine()

                Subtitle("Live Demo")
                NavigationLink(destination: BluetoothScannerView()) {
                    Text("Open BLE Scanner")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
