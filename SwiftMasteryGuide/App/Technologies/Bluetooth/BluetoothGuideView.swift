//
//  BluetoothGuideView.swift.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

import SwiftUI
import CoreBluetooth

struct BluetoothGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Title("Bluetooth Low Energy (BLE) in SwiftUI – CoreBluetooth")

                Subtitle("What you will build")
                BodyText("""
                A live BLE scanner that shows nearby devices, indicates whether they look BLE-useful, and lists advertised service names when available.
                """)

                Subtitle("Requirements")
                BulletList([
                    "iOS 15+.",
                    "Bluetooth permission in Info.plist: NSBluetoothAlwaysUsageDescription.",
                    "Framework: CoreBluetooth."
                ])

                DividerLine()

                Subtitle("How to tell if a device will work")
                BulletList([
                    "Presence of advertised service UUIDs or service data.",
                    "Is connectable flag is true.",
                    "Known standard profiles (Heart Rate 0x180D, Battery 0x180F, Device Information 0x180A, etc.).",
                    "After connecting, discovering services and characteristics succeeds."
                ])

                DividerLine()

                Subtitle("Live Demo")
                NavigationLink(destination: BluetoothScannerView()) {
                    Text("Open BLE Scanner")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(20)
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
