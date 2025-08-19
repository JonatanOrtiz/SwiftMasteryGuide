//
//  PeripheralConnectionManager.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

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
    @Published var characteristicsByService: [CBUUID : [CBCharacteristic]] = [:]
    @Published var hexLog: [String] = []
    @Published var showHIDHint: Bool = false

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wantsConnect: Bool = false
    private var notifyingCharacteristics = Set<ObjectIdentifier>()
    private var connectionTimeoutTimer: Timer?
    private var isDisconnecting = false
    private let connectionTimeoutSeconds: TimeInterval = 8.0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

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
        discoveredServices.removeAll()
        characteristicsByService.removeAll()
        hexLog.removeAll()
    }

    func connectIfNeeded() {
        guard let p = peripheral, let c = central else { return }

        wantsConnect = true

        switch c.state {
            case .poweredOn:
                if p.state == .connected {
                    stateText = "Connected"
                    p.discoverServices(nil)
                } else if p.state == .connecting {
                    stateText = "Connecting…"
                } else {
                    stateText = "Waiting for pairing…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if p.state == .disconnected {
                            self.stateText = "Connecting…"
                            c.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
                            self.startConnectionTimeout()
                        }
                    }
                }
            case .poweredOff:
                stateText = "Bluetooth is OFF"
            case .unauthorized:
                stateText = "Bluetooth permission is not granted"
            case .unsupported:
                stateText = "Bluetooth LE unsupported"
            case .resetting:
                stateText = "Bluetooth is resetting…"
            case .unknown:
                stateText = "Bluetooth state: unknown"
            @unknown default:
                stateText = "Bluetooth state: unexpected"
        }
    }

    func disconnect() {
        guard let c = central else { return }

        isDisconnecting = true
        wantsConnect = false

        if let p = peripheral {
            if p.state == .connected || p.state == .connecting {
                c.cancelPeripheralConnection(p)
                stateText = "Closing GATT connection…"

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self = self else { return }
                    if self.isDisconnecting {
                        self.stateText = "Disconnected"
                        self.isDisconnecting = false
                    }
                }
            } else {
                self.centralManager(c, didDisconnectPeripheral: p, error: nil)
            }
        }

        stopConnectionTimeout()
    }

    func teardown() {
        if !isDisconnecting {
            disconnect()
        }
        peripheral?.delegate = nil
        peripheral = nil
        discoveredServices.removeAll()
        characteristicsByService.removeAll()
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

    private func appendHex(_ data: Data?, prefix: String) {
        guard let d = data, !d.isEmpty else { return }
        let hex = d.map { String(format: "%02X", $0) }.joined(separator: " ")
        hexLog.append("\(prefix): \(hex)")
        if hexLog.count > 500 {
            hexLog.removeFirst(hexLog.count - 500)
        }
    }

    private func connectionStateText(for state: CBPeripheralState) -> String {
        switch state {
            case .disconnected: return "Disconnected"
            case .connecting:   return "Connecting…"
            case .connected:    return "Connected"
            case .disconnecting:return "Closing GATT connection…"
            @unknown default:   return "Unknown"
        }
    }

    private func startConnectionTimeout() {
        stopConnectionTimeout()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Timed out opening GATT — likely HID-only on iOS.
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
        // If user tapped Connect before BT was ready, try now.
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

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        stopConnectionTimeout()
        stateText = "Failed to connect"
        // If this is a HID-only attach, hint the right path.
        showHIDHint = true
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopConnectionTimeout()
        stateText = "GATT connection closed"
        showHIDHint = false
        isDisconnecting = false
    }
}

// MARK: - CBPeripheralDelegate
extension PeripheralConnectionManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let _ = error {
            stateText = "Service discovery failed"
            return
        }
        let services = peripheral.services ?? []
        discoveredServices = services

        // If nothing is discoverable, assume HID-only path on iOS.
        if services.isEmpty {
            showHIDHint = true
        }

        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        let chars = service.characteristics ?? []
        characteristicsByService[service.uuid] = chars
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        appendHex(characteristic.value, prefix: "Notify \(characteristic.uuid.uuidString)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        let key = ObjectIdentifier(characteristic)
        if characteristic.isNotifying {
            notifyingCharacteristics.insert(key)
        } else {
            notifyingCharacteristics.remove(key)
        }
    }
}
