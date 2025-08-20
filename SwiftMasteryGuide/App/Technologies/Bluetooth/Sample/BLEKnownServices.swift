//
//  BLEKnownServices.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import CoreBluetooth

enum BLELikelihood {
    case bleLikely
    case hidOnlyLikely
    case unknown
}

enum BLEKnownServices {
    // Standard SIG services we want to present with friendly names.
    static let namesByUUID: [CBUUID : String] = [
        CBUUID(string: "180D"): "Heart Rate",
        CBUUID(string: "180F"): "Battery",
        CBUUID(string: "180A"): "Device Information",
        CBUUID(string: "181A"): "Environmental Sensing",
        CBUUID(string: "1816"): "Cycling Speed & Cadence",
        CBUUID(string: "1814"): "Running Speed & Cadence",
        CBUUID(string: "1812"): "HID" // Human Interface Device (HOGP)
    ]

    /// Human-readable name or the raw UUID string.
    static func friendlyName(
        for uuid: CBUUID
    ) -> String {
        namesByUUID[uuid] ?? uuid.uuidString
    }

    /// Older helper kept for UI display of names, not for inference.
    static func hasMeaningfulServices(
        _ services: [CBUUID]
    ) -> Bool {
        // We consider anything in our table as "meaningful" for listing text,
        // but DO NOT use this to infer BLE-likely badges anymore.
        !services.filter { namesByUUID[$0] != nil }.isEmpty
    }

    /// New heuristic used for the badge in the scanner list.
    ///
    /// Rules of thumb:
    /// - If the only "known" service is HID (0x1812) and it is not connectable,
    ///   this is most likely a Classic HID attachment on iOS → HID-only.
    /// - If there is Service Data or any non-HID standard service, and it is connectable,
    ///   consider it BLE-likely.
    /// - If there are no services and it is not connectable, lean HID-only.
    static func likelihood(
        services: [CBUUID],
        isConnectable: Bool,
        hasServiceData: Bool,
        hasManufacturerData: Bool
    ) -> BLELikelihood {
        let set = Set(services)
        let hid = CBUUID(string: "1812")
        let hasHID = set.contains(hid)

        let knownNonHID = set.contains(CBUUID(string: "180D")) || // Heart Rate
        set.contains(CBUUID(string: "180F")) || // Battery
        set.contains(CBUUID(string: "180A")) || // Device Info
        set.contains(CBUUID(string: "181A")) || // Environmental
        set.contains(CBUUID(string: "1816")) || // Cycling
        set.contains(CBUUID(string: "1814"))    // Running

        print("""
    [BLELikelihood] Assessing likelihood:
      Services: \(services.map(\.uuidString))
      Is Connectable: \(isConnectable)
      Has Service Data: \(hasServiceData)
      Has Manufacturer Data: \(hasManufacturerData)
      Has HID: \(hasHID)
      Has Known Non-HID: \(knownNonHID)
    """)

        if knownNonHID && isConnectable {
            print("[BLELikelihood] ➜ Result: bleLikely (strong BLE indicators)")
            return .bleLikely
        }

        if hasServiceData && isConnectable {
            print("[BLELikelihood] ➜ Result: bleLikely (service data + connectable)")
            return .bleLikely
        }

        if hasHID && !isConnectable {
            print("[BLELikelihood] ➜ Result: hidOnlyLikely (only HID + not connectable)")
            return .hidOnlyLikely
        }

        if services.isEmpty && !isConnectable {
            print("[BLELikelihood] ➜ Result: hidOnlyLikely (no services + not connectable)")
            return .hidOnlyLikely
        }

        if knownNonHID || hasServiceData {
            print("[BLELikelihood] ➜ Result: bleLikely (weak BLE indicators)")
            return .bleLikely
        }

        if hasManufacturerData && isConnectable {
            print("[BLELikelihood] ➜ Result: bleLikely (manufacturer + connectable)")
            return .bleLikely
        }

        print("[BLELikelihood] ➜ Result: unknown")
        return .unknown
    }
}
