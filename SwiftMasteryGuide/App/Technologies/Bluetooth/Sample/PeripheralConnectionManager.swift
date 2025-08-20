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

    // MARK: - Public Actions

    func prepare(with peripheral: CBPeripheral?) {
        guard let p = peripheral else {
            log("prepare: peripheral is nil")
            stateText = "Peripheral unavailable"
            return
        }
        self.peripheral = p
        p.delegate = self
        meta = Meta(
            id: p.identifier,
            name: p.name ?? "Unknown",
            advertisedServices: [] // pode ajustar se quiser passar serviços
        )
        stateText = connectionStateText(for: p.state)
        showHIDHint = false
        discoveredServices = []
        characteristicsByService = [:]
        hexLog = []
        log("Prepared peripheral: \(meta?.name ?? "Unknown") (\(meta?.id.uuidString ?? ""))")
    }

    func bind(central: CBCentralManager) {
        central.delegate = self
        self.central = central
        log("Bound to central manager")
    }

    func connectIfNeeded() {
        guard let p = peripheral, let c = central else {
            log("connectIfNeeded: missing central or peripheral")
            return
        }

        wantsConnect = true
        switch c.state {
            case .poweredOn:
                switch p.state {
                    case .connected:
                        log("connectIfNeeded: already connected – discovering services")
                        stateText = "Connected"
                        p.discoverServices(nil)
                    case .connecting:
                        log("connectIfNeeded: currently connecting")
                        stateText = "Connecting…"
                    default:
                        log("connectIfNeeded: initiating connection")
                        stateText = "Waiting for pairing…"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                            guard let self else { return }
                            
                            guard p.state == .disconnected else { return }
                            log("connectIfNeeded: attempting central.connect")
                            self.stateText = "Connecting…"
                            c.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
                            self.startConnectionTimeout()
                        }
                }
            default:
                log("connectIfNeeded: central not powered on, state = \(c.state.rawValue)")
                stateText = bluetoothStateText(c.state)
        }
    }

    func disconnect() {
        guard let c = central else {
            log("disconnect: central is nil")
            return
        }

        isDisconnecting = true
        wantsConnect = false

        if let p = peripheral, (p.state == .connected || p.state == .connecting) {
            log("disconnect: cancelPeripheralConnection")
            c.cancelPeripheralConnection(p)
            stateText = "Closing GATT connection…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }

                if self.isDisconnecting {
                    self.stateText = "Disconnected"
                    self.isDisconnecting = false
                    log("disconnect: connection closed")
                }
            }
        } else {
            log("disconnect: not connected, invoking didDisconnect manually")
            centralManager(c, didDisconnectPeripheral: peripheral!, error: nil)
        }

        stopConnectionTimeout()
    }

    func teardown() {
        log("teardown: cleaning up")
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
        log("toggleNotify: \(ch.uuid.uuidString), currently notifying = \(isNotifying(ch))")
        peripheral?.setNotifyValue(!isNotifying(ch), for: ch)
    }

    func read(_ ch: CBCharacteristic) {
        log("read: \(ch.uuid.uuidString)")
        peripheral?.readValue(for: ch)
    }

    // MARK: - Private Helpers

    private func appendHex(_ data: Data?, prefix: String) {
        guard let d = data, !d.isEmpty else {
            log("\(prefix): no data to append")
            return
        }
        let hex = d.map { String(format: "%02X", $0) }.joined(separator: " ")
        hexLog.append("\(prefix): \(hex)")
        if hexLog.count > 500 {
            hexLog.removeFirst(hexLog.count - 500)
        }
        log("appendHex: \(prefix): \(hex)")
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
        log("startConnectionTimeout: scheduling in \(connectionTimeoutSeconds)s")
        stopConnectionTimeout()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stateText = "Connected as HID (no GATT)"
                self.showHIDHint = true
                self.log("Connection timeout expired — assuming HID-only")
            }
        }
    }

    private func stopConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        log("stopConnectionTimeout: timer invalidated")
    }

    private func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[PeripheralConnectionManager] [\(ts)] \(message)")
    }
}

// MARK: - CBCentralManagerDelegate
extension PeripheralConnectionManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let text = bluetoothStateText(central.state)
        stateText = text
        log("centralManagerDidUpdateState: \(text)")

        if central.state == .poweredOn, wantsConnect, let p = peripheral {
            log("central ready + wantsConnect – initiating connect")
            stateText = "Connecting…"
            central.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])
            startConnectionTimeout()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stopConnectionTimeout()
        stateText = "Connected"
        log("didConnect: \(peripheral.name ?? "") (\(peripheral.identifier)) — discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        stopConnectionTimeout()
        stateText = "Failed to connect"
        showHIDHint = true
        log("didFailToConnect: \(error?.localizedDescription ?? "no error info")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopConnectionTimeout()
        stateText = "GATT connection closed"
        showHIDHint = false
        isDisconnecting = false
        log("didDisconnectPeripheral: \(peripheral.name ?? "") — error: \(error?.localizedDescription ?? "none")")
    }
}

// MARK: - CBPeripheralDelegate
extension PeripheralConnectionManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            stateText = "Service discovery failed"
            log("didDiscoverServices: error \(err.localizedDescription)")
            return
        }

        let svcs = peripheral.services ?? []
        discoveredServices = svcs
        log("didDiscoverServices: found \(svcs.count) services")

        showHIDHint = svcs.isEmpty
        for service in svcs {
            log("→ Service: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            log("didDiscoverCharacteristicsFor \(service.uuid.uuidString): error \(err.localizedDescription)")
            return
        }

        let chars = service.characteristics ?? []
        characteristicsByService[service.uuid] = chars
        log("didDiscoverCharacteristicsFor \(service.uuid.uuidString): found \(chars.count) characteristics")

        for ch in chars {
            log("⤷ Char: \(ch.uuid.uuidString) props: \(ch.properties)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            log("didUpdateValueFor \(characteristic.uuid.uuidString): error \(err.localizedDescription)")
            return
        }
        appendHex(characteristic.value, prefix: "Notify \(characteristic.uuid.uuidString)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            log("didUpdateNotificationStateFor \(characteristic.uuid.uuidString): error \(err.localizedDescription)")
            return
        }

        let key = ObjectIdentifier(characteristic)
        if characteristic.isNotifying {
            notifyingCharacteristics.insert(key)
            log("didUpdateNotificationStateFor \(characteristic.uuid.uuidString): now notifying")
        } else {
            notifyingCharacteristics.remove(key)
            log("didUpdateNotificationStateFor \(characteristic.uuid.uuidString): stopped notifying")
        }
    }
}
