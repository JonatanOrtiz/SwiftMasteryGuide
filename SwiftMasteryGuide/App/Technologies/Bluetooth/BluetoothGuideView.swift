//
//  BluetoothGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 19/08/25.
//

import SwiftUI

/// A comprehensive guide that explains step-by-step how to build
/// a complete BLE scanner with device discovery, connection management,
/// service/characteristic exploration, and live data monitoring.
struct BluetoothGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                NavigationLink(destination: BluetoothScannerView()) {
                    Text("Open Bluetooth Scanner Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open bluetooth scanner demo")

                Title("Bluetooth Low Energy Scanner -- Complete Guide")

                Subtitle("What you'll build")
                BodyText("""
A production-ready BLE scanner that discovers nearby devices, manages GATT connections, \
explores services and characteristics, handles notifications, and provides real-time \
data monitoring with proper state management and error handling.
""")

                Subtitle("Requirements")
                BulletList([
                    "iOS 13+ (for Combine support).",
                    "Add NSBluetoothAlwaysUsageDescription to Info.plist.",
                    "Test on a real device (Simulator has limited BLE support).",
                    "Frameworks: CoreBluetooth, SwiftUI, Combine."
                ])

                DividerLine()

                Subtitle("Architecture Overview")
                BodyText("""
• BluetoothScannerViewModel → Manages device discovery, RSSI smoothing, and scan state.
• PeripheralConnectionManager → Handles GATT connections, service discovery, and notifications.
• BLEKnownServices → Maps standard UUIDs to friendly names and provides BLE/HID heuristics.
• UI Components → SwiftUI views for listing devices and exploring peripheral details.
""")

                DividerLine()

                // MARK: - Step 1: Known Services Helper

                Subtitle("Step 1) BLE Known Services Helper")
                BodyText("""
Create a helper enum that maps standard Bluetooth SIG service UUIDs to friendly names \
and provides heuristics to distinguish between BLE-likely and HID-only devices. This \
improves UX by showing meaningful service names instead of raw UUIDs.
""")
                CodeBlock("""
// FILE: BLEKnownServices.swift
import CoreBluetooth

enum BLELikelihood {
    case bleLikely
    case hidOnlyLikely
    case unknown
}

enum BLEKnownServices {
    // Standard SIG services we want to present with friendly names
    static let namesByUUID: [CBUUID : String] = [
        CBUUID(string: "180D"): "Heart Rate",
        CBUUID(string: "180F"): "Battery",
        CBUUID(string: "180A"): "Device Information",
        CBUUID(string: "181A"): "Environmental Sensing",
        CBUUID(string: "1816"): "Cycling Speed & Cadence",
        CBUUID(string: "1814"): "Running Speed & Cadence",
        CBUUID(string: "1812"): "HID" // Human Interface Device (HOGP)
    ]

    /// Human-readable name or the raw UUID string
    static func friendlyName(for uuid: CBUUID) -> String {
        namesByUUID[uuid] ?? uuid.uuidString
    }

    /// Heuristic to determine if device is BLE-likely or HID-only
    /// Rules:
    /// - If only HID service + not connectable → HID-only likely
    /// - If has service data or non-HID services + connectable → BLE-likely
    /// - Empty services + not connectable → HID-only likely
    static func likelihood(
        services: [CBUUID],
        isConnectable: Bool,
        hasServiceData: Bool,
        hasManufacturerData: Bool
    ) -> BLELikelihood {
        let set = Set(services)
        let hid = CBUUID(string: "1812")
        let hasHID = set.contains(hid)
        
        // Check for known non-HID services
        let knownNonHID = set.contains { uuid in
            namesByUUID[uuid] != nil && uuid != hid
        }
        
        // Strong BLE indicators
        if knownNonHID && isConnectable {
            return .bleLikely
        }
        
        if hasServiceData && isConnectable {
            return .bleLikely
        }
        
        // HID-only indicators
        if hasHID && !isConnectable {
            return .hidOnlyLikely
        }
        
        if services.isEmpty && !isConnectable {
            return .hidOnlyLikely
        }
        
        // Weak BLE indicators
        if knownNonHID || hasServiceData {
            return .bleLikely
        }
        
        if hasManufacturerData && isConnectable {
            return .bleLikely
        }
        
        return .unknown
    }
}
""")

                // MARK: - Step 2: Device Discovery ViewModel

                Subtitle("Step 2) Bluetooth Scanner ViewModel")
                BodyText("""
The main ViewModel manages CBCentralManager, discovers peripherals, applies RSSI smoothing \
for stable signal readings, and publishes the device list to SwiftUI. It uses a throttled \
UI update mechanism to prevent excessive refreshes while maintaining responsiveness.
""")
                CodeBlock("""
// FILE: BluetoothScannerViewModel.swift
import SwiftUI
import CoreBluetooth

struct DiscoveredPeripheral: Identifiable, Hashable {
    let id: UUID
    let name: String
    let isConnectable: Bool
    let advertisedServices: [CBUUID]
    let hasServiceData: Bool
    let hasManufacturerData: Bool
    let rssi: Int
}

// Internal mutable structure for tracking
private struct MutablePeripheral {
    let id: UUID
    var name: String
    var isConnectable: Bool
    var advertisedServices: [CBUUID]
    var hasServiceData: Bool
    var hasManufacturerData: Bool
    var smoothedRSSI: Double
    var lastRawRSSI: Int
}

final class BluetoothScannerViewModel: NSObject, ObservableObject {
    
    @Published var stateText: String = "Waiting for Bluetooth…"
    @Published var items: [DiscoveredPeripheral] = []
    @Published var sortBySignal: Bool = false
    
    private var central: CBCentralManager?
    private var seen: [UUID: MutablePeripheral] = [:]
    private var order: [UUID] = []  // Maintains discovery order
    private let rssiAlpha: Double = 0.25  // RSSI smoothing factor
    private var lastUIRefresh: CFAbsoluteTime = 0
    private let minUIRefreshInterval: CFTimeInterval = 0.5
    private var lastResortTime: CFAbsoluteTime = 0
    private let minResortInterval: CFTimeInterval = 2.0
    private var peripheralById: [UUID: CBPeripheral] = [:]
    private var isScanning = false
    
    // Expose central for connection manager
    var centralManager: CBCentralManager? { central }
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard let central else { return }
        guard central.state == .poweredOn else { return }
        
        isScanning = true
        central.scanForPeripherals(
            withServices: nil,  // Scan for all devices
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        stateText = "Scanning…"
    }
    
    func stopScanning() {
        central?.stopScan()
        isScanning = false
        stateText = "Stopped"
        
        // Clear state
        seen.removeAll()
        order.removeAll()
        peripheralById.removeAll()
        
        DispatchQueue.main.async { [weak self] in
            self?.items = []
        }
    }
    
    func cbPeripheral(for id: UUID) -> CBPeripheral? {
        peripheralById[id]
    }
    
    // Throttled UI updates to prevent excessive refreshes
    private func rebuildItemsIfNeeded(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || (now - lastUIRefresh) >= minUIRefreshInterval else { return }
        lastUIRefresh = now
        
        // Determine order based on sort preference
        let ids: [UUID]
        if sortBySignal {
            // Re-sort periodically, not on every update
            if now - lastResortTime >= minResortInterval {
                lastResortTime = now
                ids = seen
                    .sorted { $0.value.smoothedRSSI > $1.value.smoothedRSSI }
                    .map { $0.key }
            } else {
                ids = items.map { $0.id }  // Keep current order
            }
        } else {
            ids = order  // Discovery order
        }
        
        // Build immutable array for SwiftUI
        var out: [DiscoveredPeripheral] = []
        out.reserveCapacity(ids.count)
        for id in ids {
            guard let m = seen[id] else { continue }
            out.append(
                DiscoveredPeripheral(
                    id: id,
                    name: m.name,
                    isConnectable: m.isConnectable,
                    advertisedServices: m.advertisedServices,
                    hasServiceData: m.hasServiceData,
                    hasManufacturerData: m.hasManufacturerData,
                    rssi: Int(m.smoothedRSSI.rounded())
                )
            )
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.items = out
        }
    }
    
    // Exponential moving average for RSSI smoothing
    private func smoothRSSI(previous: Double?, new: Int) -> Double {
        let p = previous ?? Double(new)
        return rssiAlpha * Double(new) + (1 - rssiAlpha) * p
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothScannerViewModel: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            stateText = "Bluetooth state: unknown"
        case .resetting:
            stateText = "Bluetooth is resetting…"
        case .unsupported:
            stateText = "Bluetooth LE is unsupported on this device"
        case .unauthorized:
            stateText = "Bluetooth permission is not granted"
        case .poweredOff:
            stateText = "Bluetooth is OFF"
        case .poweredOn:
            stateText = "Bluetooth is ON"
        @unknown default:
            stateText = "Bluetooth state: unexpected"
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning else { return }
        
        // Extract peripheral info from advertisement
        let name = peripheral.name 
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        
        // Collect all advertised services
        var services: [CBUUID] = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            services.append(contentsOf: overflow)
        }
        
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID : Data]
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        
        let id = peripheral.identifier
        let newRssi = RSSI.intValue
        
        // Store CBPeripheral reference for later connection
        peripheralById[id] = peripheral
        
        // Update or create peripheral entry
        if var existing = seen[id] {
            // Update existing entry
            existing.name = name
            existing.isConnectable = isConnectable
            existing.advertisedServices = services
            existing.hasServiceData = (serviceData?.isEmpty == false)
            existing.hasManufacturerData = (manufacturerData?.isEmpty == false)
            existing.lastRawRSSI = newRssi
            existing.smoothedRSSI = smoothRSSI(previous: existing.smoothedRSSI, new: newRssi)
            seen[id] = existing
        } else {
            // New peripheral discovered
            let smoothed = smoothRSSI(previous: nil, new: newRssi)
            seen[id] = MutablePeripheral(
                id: id,
                name: name,
                isConnectable: isConnectable,
                advertisedServices: services,
                hasServiceData: (serviceData?.isEmpty == false),
                hasManufacturerData: (manufacturerData?.isEmpty == false),
                smoothedRSSI: smoothed,
                lastRawRSSI: newRssi
            )
            order.append(id)
        }
        
        rebuildItemsIfNeeded()
    }
}
""")

                // MARK: - Step 3: Connection Manager

                Subtitle("Step 3) Peripheral Connection Manager")
                BodyText("""
A dedicated manager for handling GATT connections, service discovery, characteristic \
exploration, and notifications. It provides clean separation of concerns and manages \
the complex CBPeripheral delegate callbacks with proper state tracking.
""")
                CodeBlock("""
// FILE: PeripheralConnectionManager.swift
import Foundation
import CoreBluetooth
import SwiftUI

@MainActor
final class PeripheralConnectionManager: NSObject, ObservableObject {
    
    struct Meta {
        let id: UUID
        let name: String
        let advertisedServices: [CBUUID]
    }
    
    @Published var meta: Meta?
    @Published var stateText: String = "Idle"
    @Published var discoveredServices: [CBService] = []
    @Published var characteristicsByService: [CBUUID: [CBCharacteristic]] = [:]
    @Published var hexLog: [String] = []
    @Published var showHIDHint: Bool = false
    
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wantsConnect: Bool = false
    private var notifyingCharacteristics = Set<ObjectIdentifier>()
    private var connectionTimeoutTimer: Timer?
    private var isDisconnecting = false
    private let connectionTimeoutSeconds: TimeInterval = 8.0
    
    // MARK: - Public Interface
    
    func prepare(with peripheral: CBPeripheral?) {
        guard let p = peripheral else {
            stateText = "Peripheral unavailable"
            return
        }
        self.peripheral = p
        p.delegate = self
        meta = Meta(
            id: p.identifier,
            name: p.name ?? "Unknown",
            advertisedServices: []
        )
        stateText = connectionStateText(for: p.state)
        showHIDHint = false
        discoveredServices = []
        characteristicsByService = [:]
        hexLog = []
    }
    
    func bind(central: CBCentralManager) {
        central.delegate = self
        self.central = central
    }
    
    func connectIfNeeded() {
        guard let p = peripheral, let c = central else { return }
        
        wantsConnect = true
        switch c.state {
        case .poweredOn:
            switch p.state {
            case .connected:
                stateText = "Connected"
                p.discoverServices(nil)
            case .connecting:
                stateText = "Connecting…"
            default:
                // Add delay for pairing dialog if needed
                stateText = "Waiting for pairing…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self else { return }
                    guard p.state == .disconnected else { return }
                    self.stateText = "Connecting…"
                    c.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
                    self.startConnectionTimeout()
                }
            }
        default:
            stateText = bluetoothStateText(c.state)
        }
    }
    
    func disconnect() {
        guard let c = central else { return }
        
        isDisconnecting = true
        wantsConnect = false
        
        if let p = peripheral, (p.state == .connected || p.state == .connecting) {
            c.cancelPeripheralConnection(p)
            stateText = "Closing GATT connection…"
            
            // Ensure UI updates after disconnect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                if self.isDisconnecting {
                    self.stateText = "Disconnected"
                    self.isDisconnecting = false
                }
            }
        } else {
            // Already disconnected
            centralManager(c, didDisconnectPeripheral: peripheral!, error: nil)
        }
        
        stopConnectionTimeout()
    }
    
    func teardown() {
        if !isDisconnecting {
            disconnect()
        }
        peripheral?.delegate = nil
        peripheral = nil
        discoveredServices = []
        characteristicsByService = [:]
        notifyingCharacteristics.removeAll()
        hexLog.removeAll()
        showHIDHint = false
    }
    
    func isNotifying(_ ch: CBCharacteristic) -> Bool {
        notifyingCharacteristics.contains(ObjectIdentifier(ch))
    }
    
    func toggleNotify(for ch: CBCharacteristic) {
        peripheral?.setNotifyValue(!isNotifying(ch), for: ch)
    }
    
    func read(_ ch: CBCharacteristic) {
        peripheral?.readValue(for: ch)
    }
    
    // MARK: - Private Helpers
    
    private func appendHex(_ data: Data?, prefix: String) {
        guard let d = data, !d.isEmpty else { return }
        let hex = d.map { String(format: "%02X", $0) }.joined(separator: " ")
        hexLog.append("\\(prefix): \\(hex)")
        // Limit log size
        if hexLog.count > 500 {
            hexLog.removeFirst(hexLog.count - 500)
        }
    }
    
    private func connectionStateText(for state: CBPeripheralState) -> String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnecting: return "Closing GATT connection…"
        @unknown default: return "Unknown"
        }
    }
    
    private func bluetoothStateText(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Bluetooth state: unknown"
        case .resetting: return "Bluetooth is resetting…"
        case .unsupported: return "Bluetooth LE unsupported"
        case .unauthorized: return "Bluetooth permission is not granted"
        case .poweredOff: return "Bluetooth is OFF"
        case .poweredOn: return "Bluetooth is ON"
        @unknown default: return "Bluetooth state: unexpected"
        }
    }
    
    private func startConnectionTimeout() {
        stopConnectionTimeout()
        connectionTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: connectionTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stateText = "Connected as HID (no GATT)"
                self.showHIDHint = true
            }
        }
    }
    
    private func stopConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension PeripheralConnectionManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let text = bluetoothStateText(central.state)
        stateText = text
        
        // Auto-reconnect if Bluetooth becomes available
        if central.state == .poweredOn, wantsConnect, let p = peripheral {
            stateText = "Connecting…"
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
            startConnectionTimeout()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stopConnectionTimeout()
        stateText = "Connected"
        peripheral.discoverServices(nil)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        stopConnectionTimeout()
        stateText = "Failed to connect"
        showHIDHint = true
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stopConnectionTimeout()
        stateText = "GATT connection closed"
        showHIDHint = false
        isDisconnecting = false
    }
}

// MARK: - CBPeripheralDelegate
extension PeripheralConnectionManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            stateText = "Service discovery failed"
            return
        }
        
        let svcs = peripheral.services ?? []
        discoveredServices = svcs
        showHIDHint = svcs.isEmpty  // Likely HID if no GATT services
        
        for service in svcs {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if error != nil { return }
        
        let chars = service.characteristics ?? []
        characteristicsByService[service.uuid] = chars
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if error != nil { return }
        appendHex(characteristic.value, prefix: "Notify \\(characteristic.uuid.uuidString)")
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if error != nil { return }
        
        let key = ObjectIdentifier(characteristic)
        if characteristic.isNotifying {
            notifyingCharacteristics.insert(key)
        } else {
            notifyingCharacteristics.remove(key)
        }
    }
}
""")

                // MARK: - Step 4: Scanner View

                Subtitle("Step 4) Bluetooth Scanner View")
                BodyText("""
The main scanner UI that lists discovered devices with their signal strength, \
advertised services, and provides navigation to the detail view. It includes \
controls for starting/stopping scans and sorting options.
""")
                CodeBlock("""
// FILE: BluetoothScannerView.swift
import SwiftUI

struct BluetoothScannerView: View {
    @StateObject private var vm = BluetoothScannerViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("BLE Device Scanner")
            BodyText("Scan for nearby BLE devices and inspect their services in a detail view.")
            
            Text(vm.stateText)
                .foregroundColor(.textSecondary)
                .accessibilityLabel("Bluetooth state \\(vm.stateText)")
            
            Toggle(isOn: $vm.sortBySignal) {
                Text("Sort by signal (throttled)")
                    .font(.system(size: 14))
            }
            .padding(.trailing, 8)
            .accessibilityLabel("Sort devices by signal strength")
            
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

// MARK: - Device List Section
private struct BLEDevicesSection: View {
    let items: [DiscoveredPeripheral]
    let viewModelProvider: () -> BluetoothScannerViewModel
    
    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink(
                        destination: PeripheralDetailView(
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

// MARK: - Device Row
private struct BLEDeviceRow: View {
    let item: DiscoveredPeripheral
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .accessibilityLabel("Device \\(item.name)")
                
                // Show preview of advertised services
                let servicesPreview = item.advertisedServices
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
                // Signal strength
                Text("\\(item.rssi) dBm")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .accessibilityLabel("Signal \\(item.rssi) dBm")
                
                // Service count badge
                let servicesCount = item.advertisedServices.count
                if servicesCount > 0 {
                    Label(
                        "Services in ad: \\(servicesCount)",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel("Services in advertisement \\(servicesCount)")
                } else {
                    Label(
                        "Advertisement only",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel("Advertisement only")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Controls Bar
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
""")

                // MARK: - Step 5: Peripheral Detail View

                Subtitle("Step 5) Peripheral Detail View")
                BodyText("""
The detail view for exploring a specific peripheral. It manages GATT connections, \
displays discovered services and characteristics, allows subscribing to notifications, \
reading values, and shows a live hex log of all received data.
""")
                CodeBlock("""
// FILE: PeripheralDetailView.swift
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
                
                // Peripheral metadata
                if let meta = connector.meta {
                    BodyText("Name: \\(meta.name)")
                    BodyText("Identifier: \\(meta.id.uuidString)")
                    BodyText("State: \\(connector.stateText)")
                    
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
                
                // Connection controls
                HStack(spacing: 12) {
                    Button("Connect") {
                        let vm = viewModelProvider()
                        vm.stopScanning()  // Stop scanning to save battery
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
                
                // Discovered services and characteristics
                Subtitle("Discovered Services")
                if connector.discoveredServices.isEmpty {
                    BodyText("—")
                } else {
                    ForEach(connector.discoveredServices, id: \\.uuid) { service in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(BLEKnownServices.friendlyName(for: service.uuid))
                                .font(.system(size: 16, weight: .semibold))
                            
                            if let chars = connector.characteristicsByService[service.uuid] {
                                ForEach(chars, id: \\.uuid) { ch in
                                    HStack {
                                        Text("• \\(ch.uuid.uuidString)")
                                            .font(.system(size: 14))
                                        Spacer()
                                        
                                        // Notify button if characteristic supports it
                                        if ch.properties.contains(.notify) {
                                            Button(
                                                connector.isNotifying(ch) 
                                                    ? "Unsubscribe" 
                                                    : "Subscribe"
                                            ) {
                                                connector.toggleNotify(for: ch)
                                            }
                                            .font(.system(size: 12, weight: .semibold))
                                        }
                                        
                                        // Read button if characteristic supports it
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
                
                // Live hex log
                Subtitle("Live Log (HEX)")
                ScrollView {
                    Text(connector.hexLog.joined(separator: "\\n"))
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
                
                // HID-only hint
                if connector.showHIDHint {
                    DividerLine()
                    Text("⚠️ This peripheral may be a HID-only device. On iOS, access to GATT is restricted for some devices.")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
            .padding(20)
        }
        .navigationTitle("Peripheral")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Setup connection manager with scanner's central
            let vm = viewModelProvider()
            if let c = vm.centralManager {
                connector.bind(central: c)
            }
            let cb = vm.cbPeripheral(for: peripheralId)
            connector.prepare(with: cb)
            vm.stopScanning()  // Stop scanning while in detail view
        }
        .onDisappear {
            connector.teardown()  // Clean up on exit
        }
    }
}
""")

                DividerLine()

                // MARK: - Implementation Tips

                Subtitle("Implementation Tips & Best Practices")
                BulletList([
                    "Always check Bluetooth state before scanning or connecting.",
                    "Use RSSI smoothing (exponential moving average) for stable signal readings.",
                    "Throttle UI updates to prevent excessive SwiftUI re-renders.",
                    "Stop scanning when not needed to save battery.",
                    "Handle connection timeouts for HID-only devices gracefully.",
                    "Keep strong references to CBPeripheral objects during connection.",
                    "Use weak self in closures to prevent retain cycles.",
                    "Limit hex log size to prevent memory growth.",
                    "Test with various BLE devices (heart rate monitors, beacons, HID devices)."
                ])

                DividerLine()

                // MARK: - Info.plist Configuration

                Subtitle("Info.plist Configuration")
                BodyText("Add the following key to your Info.plist to request Bluetooth permission:")
                CodeBlock("""
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover and connect to nearby BLE devices.</string>
""")

                DividerLine()

                // MARK: - Common Issues & Solutions

                Subtitle("Common Issues & Solutions")

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Issue: Devices not appearing in scan")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Solution: Ensure Bluetooth is ON, app has permission, and device is advertising.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Issue: Can't connect to device")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Solution: Device may be HID-only (keyboard/mouse), already connected elsewhere, or requires pairing in Settings first.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Issue: No services discovered")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Solution: iOS restricts GATT access for HID devices. The device shows as connected but services are hidden.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Issue: Notifications not working")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Solution: Ensure characteristic supports notify/indicate property and device is sending data.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }

                DividerLine()

                // MARK: - Advanced Features

                Subtitle("Advanced Features to Consider")
                BulletList([
                    "Background scanning with CBCentralManagerOptionRestoreIdentifierKey.",
                    "Filtering by service UUID for targeted discovery.",
                    "Writing values to characteristics (add write support).",
                    "Parsing manufacturer data for iBeacon/Eddystone detection.",
                    "Implementing reconnection logic with exponential backoff.",
                    "Adding data persistence with Core Data or SwiftData.",
                    "Creating custom parsers for known GATT profiles.",
                    "Implementing OTA firmware updates via BLE.",
                    "Adding signal strength visualization with charts."
                ])

                DividerLine()

                // MARK: - Testing Checklist

                Subtitle("Testing Checklist")
                BulletList([
                    "✓ Test with Bluetooth OFF → should show appropriate message.",
                    "✓ Test with permission denied → should guide user to Settings.",
                    "✓ Test with no devices nearby → should show empty list.",
                    "✓ Test with multiple devices → should handle high volume.",
                    "✓ Test rapid connect/disconnect → should handle state changes.",
                    "✓ Test with HID devices → should show HID hint.",
                    "✓ Test with BLE beacons → should show advertisement data.",
                    "✓ Test background/foreground transitions → should maintain state.",
                    "✓ Test memory usage during long scans → should be stable."
                ])

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("BLE Scanner Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
