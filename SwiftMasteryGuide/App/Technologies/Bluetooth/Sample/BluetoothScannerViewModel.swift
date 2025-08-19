//
//  BluetoothScannerViewModel.swift.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

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
    private var order: [UUID] = []
    private let rssiAlpha: Double = 0.25
    private var lastUIRefresh: CFAbsoluteTime = 0
    private let minUIRefreshInterval: CFTimeInterval = 0.5
    private var lastResortTime: CFAbsoluteTime = 0
    private let minResortInterval: CFTimeInterval = 2.0

    private var peripheralById: [UUID: CBPeripheral] = [:]
    private var isScanning = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard let central, central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        stateText = "Scanning…"
    }

    func stopScanning() {
        central?.stopScan()
        isScanning = false
        stateText = "Stopped"

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

    private func rebuildItemsIfNeeded(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || (now - lastUIRefresh) >= minUIRefreshInterval else { return }
        lastUIRefresh = now

        let ids: [UUID]
        if sortBySignal {
            if now - lastResortTime >= minResortInterval {
                lastResortTime = now
                ids = seen
                    .sorted { $0.value.smoothedRSSI > $1.value.smoothedRSSI }
                    .map { $0.key }
            } else {
                ids = items.map { $0.id }
            }
        } else {
            ids = order
        }

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

    private func smoothRSSI(previous: Double?, new: Int) -> Double {
        let p = previous ?? Double(new)
        return rssiAlpha * Double(new) + (1 - rssiAlpha) * p
    }
}

extension BluetoothScannerViewModel: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .unknown: stateText = "Bluetooth state: unknown"
            case .resetting: stateText = "Bluetooth is resetting…"
            case .unsupported: stateText = "Bluetooth LE is unsupported on this device"
            case .unauthorized: stateText = "Bluetooth permission is not granted"
            case .poweredOff: stateText = "Bluetooth is OFF"
            case .poweredOn: stateText = "Bluetooth is ON"
            @unknown default: stateText = "Bluetooth state: unexpected"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning else { return }

        let name: String = peripheral.name
        ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? "Unknown"

        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        var services: [CBUUID] = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            services.append(contentsOf: overflow)
        }

        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID : Data]
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        let id = peripheral.identifier
        let newRssi = RSSI.intValue

        peripheralById[id] = peripheral

        if var existing = seen[id] {
            existing.name = name
            existing.isConnectable = isConnectable
            existing.advertisedServices = services
            existing.hasServiceData = (serviceData?.isEmpty == false)
            existing.hasManufacturerData = (manufacturerData?.isEmpty == false)
            existing.lastRawRSSI = newRssi
            existing.smoothedRSSI = smoothRSSI(previous: existing.smoothedRSSI, new: newRssi)
            seen[id] = existing
        } else {
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
