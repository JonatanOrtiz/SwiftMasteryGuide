//
//  GameControllerInputManager.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 18/08/25.
//

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

    // MARK: - Discovery & attachment

    func discoverControllers() {
        // Kick off discovery in case the controller was paired but not yet exposed to the app.
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

    // MARK: - Notifications

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
        if let c = controllerObservation { center.removeObserver(c) }
        if let d = disconnectObservation { center.removeObserver(d) }
        controllerObservation = nil
        disconnectObservation = nil
    }

    // MARK: - Wiring & publishing

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

        // Unknown profile
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
