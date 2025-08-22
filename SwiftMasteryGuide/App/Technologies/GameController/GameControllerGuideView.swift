//
//  GameControllerGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 19/08/25.
//

import SwiftUI
import GameController

struct GameControllerGuideView: View {

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                NavigationLink(destination: GameControllerView()) {
                    Text("Open Controllers List")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open controllers list")

                // Lesson Intro
                Title("GameController – Overview")
                BodyText("""
                The GameController framework provides a unified way to discover and read input from HID game controllers on iOS, iPadOS, tvOS, and macOS. \
                You can discover wireless controllers, observe connection changes, and consume input from common profiles such as Extended Gamepad or Micro Gamepad.
                """)

                DividerLine()

                // Learning goals
                Subtitle("What You Will Learn")
                BulletList([
                    "How to discover controllers and observe connection events.",
                    "How to read input from buttons, thumbsticks, D‑Pad and triggers.",
                    "How to structure a reusable input manager for clean UI updates.",
                    "How to present a controller list and a live input demo screen."
                ])

                DividerLine()

                // Example 1 — Listing controllers
                Subtitle("Example: Listing Connected Controllers")
                BodyText("""
                Use `GCController.controllers()` to access the current controllers and present a simple list. \
                Trigger discovery with `GCController.startWirelessControllerDiscovery(_:)` to ensure devices paired in Settings become available to your app.
                """)

                CodeBlock(
                """
                import GameController
                
                struct GameControllerView: View {
                    @State private var controllers: [GCController] = []
                
                    var body: some View {
                        VStack(alignment: .leading, spacing: 16) {
                            Title("Game Controllers")
                            BodyText("This screen lists HID game controllers detected by iOS.")
                
                            Subtitle("Game Controllers (HID)")
                            if controllers.isEmpty {
                                BodyText("No controllers detected via GameController. If your controller is connected in Settings but not listed here, it might be using keyboard/iCade mode.")
                            } else {
                                List {
                                    Section {
                                        ForEach(controllers.indices, id: .self) { index in
                                            ControllerRow(controller: controllers[index])
                                        }
                                    }
                                }
                                .transaction { transaction in
                                    transaction.disablesAnimations = true
                                }
                            }
                
                            Button("Refresh Controllers") {
                                refreshControllers()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dividerColor, lineWidth: 1)
                            )
                            .accessibilityLabel("Refresh game controllers")
                        }
                        .padding(20)
                        .onAppear {
                            GCController.shouldMonitorBackgroundEvents = true
                            GCController.stopWirelessControllerDiscovery()
                            GCController.startWirelessControllerDiscovery { }
                            refreshControllers()
                            NotificationCenter.default.addObserver(
                                forName: .GCControllerDidConnect,
                                object: nil,
                                queue: .main
                            ) { _ in
                                refreshControllers()
                            }
                            NotificationCenter.default.addObserver(
                                forName: .GCControllerDidDisconnect,
                                object: nil,
                                queue: .main
                            ) { _ in
                                refreshControllers()
                            }
                        }
                        .onDisappear {
                            GCController.stopWirelessControllerDiscovery()
                        }
                    }
                
                    private func refreshControllers() {
                        controllers = GCController.controllers()
                    }
                }
                """
                )

                BodyText("""
                The snippet above refreshes the list whenever a controller connects or disconnects. \
                The UI is kept responsive and accessible by avoiding forced unwraps and providing labels.
                """)

                DividerLine()

                // Example 2 — Live input
                Subtitle("Example: Reading Live Input")
                BodyText("""
                For continuous input, wire the controller profile’s `valueChangedHandler` to publish an immutable snapshot. \
                A dedicated `ObservableObject` keeps the UI code lean and avoids retain cycles by using `[weak self]` in closures.
                """)

                CodeBlock(
                """
                import Foundation
                import GameController
                
                final class GameControllerInputManager: ObservableObject {
                
                    struct ControllerSnapshot: Equatable {
                        var name: String
                        var vendorName: String?
                        var isAttachedToDevice: Bool
                        var buttonSouthPressed: Bool
                        var buttonEastPressed: Bool
                        var buttonWestPressed: Bool
                        var buttonNorthPressed: Bool
                        var leftShoulderPressed: Bool
                        var rightShoulderPressed: Bool
                        var leftTrigger: Float
                        var rightTrigger: Float
                        var dpadX: Float
                        var dpadY: Float
                        var leftThumbstickX: Float
                        var leftThumbstickY: Float
                        var rightThumbstickX: Float
                        var rightThumbstickY: Float
                        var menuPressed: Bool
                    }
                
                    @Published var isControllerConnected: Bool = false
                    @Published var snapshot: ControllerSnapshot = ControllerSnapshot(
                        name: "No Controller",
                        vendorName: nil,
                        isAttachedToDevice: false,
                        buttonSouthPressed: false,
                        buttonEastPressed: false,
                        buttonWestPressed: false,
                        buttonNorthPressed: false,
                        leftShoulderPressed: false,
                        rightShoulderPressed: false,
                        leftTrigger: 0,
                        rightTrigger: 0,
                        dpadX: 0,
                        dpadY: 0,
                        leftThumbstickX: 0,
                        leftThumbstickY: 0,
                        rightThumbstickX: 0,
                        rightThumbstickY: 0,
                        menuPressed: false
                    )
                
                    private var controllerObservation: NSObjectProtocol?
                    private var disconnectObservation: NSObjectProtocol?
                    private var pollTimer: Timer?
                
                    init() {
                        startObserving()
                        discoverControllers()
                        attachToFirstAvailableController()
                        startPollingAttachment()
                    }
                
                    deinit {
                        stopObserving()
                        stopPollingAttachment()
                        GCController.stopWirelessControllerDiscovery()
                    }
                
                    func discoverControllers() {
                        GCController.startWirelessControllerDiscovery { }
                    }
                
                    func attachToFirstAvailableController() {
                        guard let controller = GCController.controllers().first else {
                            isControllerConnected = false
                            return
                        }
                        isControllerConnected = true
                        wireHandlers(for: controller)
                        publishSnapshot(from: controller)
                    }
                
                    private func startPollingAttachment() {
                        stopPollingAttachment()
                        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                            self?.attachToFirstAvailableController()
                        }
                    }
                
                    private func stopPollingAttachment() {
                        pollTimer?.invalidate()
                        pollTimer = nil
                    }
                
                    func startObserving() {
                        let center = NotificationCenter.default
                        controllerObservation = center.addObserver(
                            forName: .GCControllerDidConnect,
                            object: nil,
                            queue: .main
                        ) { [weak self] _ in
                            self?.attachToFirstAvailableController()
                        }
                        disconnectObservation = center.addObserver(
                            forName: .GCControllerDidDisconnect,
                            object: nil,
                            queue: .main
                        ) { [weak self] _ in
                            self?.isControllerConnected = false
                            self?.snapshot = ControllerSnapshot(
                                name: "No Controller",
                                vendorName: nil,
                                isAttachedToDevice: false,
                                buttonSouthPressed: false,
                                buttonEastPressed: false,
                                buttonWestPressed: false,
                                buttonNorthPressed: false,
                                leftShoulderPressed: false,
                                rightShoulderPressed: false,
                                leftTrigger: 0,
                                rightTrigger: 0,
                                dpadX: 0,
                                dpadY: 0,
                                leftThumbstickX: 0,
                                leftThumbstickY: 0,
                                rightThumbstickX: 0,
                                rightThumbstickY: 0,
                                menuPressed: false
                            )
                        }
                    }
                
                    func stopObserving() {
                        let center = NotificationCenter.default
                        if let c = controllerObservation {
                            center.removeObserver(c)
                        }
                        if let d = disconnectObservation {
                            center.removeObserver(d)
                        }
                        controllerObservation = nil
                        disconnectObservation = nil
                    }
                
                    private func wireHandlers(for controller: GCController) {
                        if let profile = controller.extendedGamepad {
                            profile.valueChangedHandler = { [weak self] _, _ in
                                self?.publishSnapshot(from: controller)
                            }
                        } else if let micro = controller.microGamepad {
                            micro.reportsAbsoluteDpadValues = true
                            micro.valueChangedHandler = { [weak self] _, _ in
                                self?.publishSnapshot(from: controller)
                            }
                        }
                    }
                
                    private func publishSnapshot(from controller: GCController) {
                        if let gp = controller.extendedGamepad {
                            snapshot = ControllerSnapshot(
                                name: controller.productCategory,
                                vendorName: controller.vendorName,
                                isAttachedToDevice: controller.isAttachedToDevice,
                                buttonSouthPressed: gp.buttonA.isPressed,
                                buttonEastPressed: gp.buttonB.isPressed,
                                buttonWestPressed: gp.buttonX.isPressed,
                                buttonNorthPressed: gp.buttonY.isPressed,
                                leftShoulderPressed: gp.leftShoulder.isPressed,
                                rightShoulderPressed: gp.rightShoulder.isPressed,
                                leftTrigger: gp.leftTrigger.value,
                                rightTrigger: gp.rightTrigger.value,
                                dpadX: gp.dpad.xAxis.value,
                                dpadY: gp.dpad.yAxis.value,
                                leftThumbstickX: gp.leftThumbstick.xAxis.value,
                                leftThumbstickY: gp.leftThumbstick.yAxis.value,
                                rightThumbstickX: gp.rightThumbstick.xAxis.value,
                                rightThumbstickY: gp.rightThumbstick.yAxis.value,
                                menuPressed: gp.buttonMenu.isPressed
                            )
                            return
                        }
                
                        if let micro = controller.microGamepad {
                            snapshot = ControllerSnapshot(
                                name: controller.productCategory,
                                vendorName: controller.vendorName,
                                isAttachedToDevice: controller.isAttachedToDevice,
                                buttonSouthPressed: micro.buttonA.isPressed,
                                buttonEastPressed: micro.buttonX.isPressed,
                                buttonWestPressed: false,
                                buttonNorthPressed: false,
                                leftShoulderPressed: false,
                                rightShoulderPressed: false,
                                leftTrigger: 0,
                                rightTrigger: 0,
                                dpadX: micro.dpad.xAxis.value,
                                dpadY: micro.dpad.yAxis.value,
                                leftThumbstickX: 0,
                                leftThumbstickY: 0,
                                rightThumbstickX: 0,
                                rightThumbstickY: 0,
                                menuPressed: micro.buttonMenu.isPressed
                            )
                            return
                        }
                
                        snapshot = ControllerSnapshot(
                            name: controller.vendorName ?? "Game Controller",
                            vendorName: controller.vendorName,
                            isAttachedToDevice: controller.isAttachedToDevice,
                            buttonSouthPressed: false,
                            buttonEastPressed: false,
                            buttonWestPressed: false,
                            buttonNorthPressed: false,
                            leftShoulderPressed: false,
                            rightShoulderPressed: false,
                            leftTrigger: 0,
                            rightTrigger: 0,
                            dpadX: 0,
                            dpadY: 0,
                            leftThumbstickX: 0,
                            leftThumbstickY: 0,
                            rightThumbstickX: 0,
                            rightThumbstickY: 0,
                            menuPressed: false
                        )
                    }
                }
                """
                )

                BodyText("""
                The manager above publishes a snapshot that your SwiftUI views can render efficiently. \
                It avoids memory leaks by removing observers in `deinit` and using `[weak self]` in closures.
                """)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("GameController")
        .navigationBarTitleDisplayMode(.inline)
    }
}
