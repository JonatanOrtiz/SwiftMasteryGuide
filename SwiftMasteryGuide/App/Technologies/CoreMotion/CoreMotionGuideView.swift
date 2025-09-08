//
//  CoreMotionGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 08/09/25.
//

import SwiftUI
import CoreMotion

struct CoreMotionGuideView: View {

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                NavigationLink(destination: TiltMazeDemoView()) {
                    Text("Open Tilt Maze Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open tilt maze demo")

                // Lesson Intro
                Title("CoreMotion – Tilt Maze Game")
                BodyText("""
                CoreMotion provides access to motion data from device sensors including accelerometer, gyroscope, and magnetometer. \
                Build immersive experiences that respond to device movement, orientation changes, and user gestures through tilt controls.
                """)

                DividerLine()

                // Learning goals
                Subtitle("What You Will Learn")
                BulletList([
                    "How to access device motion data using CMMotionManager.",
                    "How to implement tilt controls with low-pass filtering for smooth movement.",
                    "How to create physics-based games with SpriteKit and CoreMotion.",
                    "How to handle device orientation changes and coordinate mapping."
                ])

                DividerLine()

                // Example 1 — Motion Manager Setup
                Subtitle("Example: Setting Up Motion Manager")
                BodyText("""
                Create a motion manager to access device motion data. Use low-pass filtering to smooth sensor readings \
                and map device coordinates to your game's coordinate system based on current orientation.
                """)

                CodeBlock(
                """
                import CoreMotion
                import Combine
                
                final class MotionManager {
                    struct GravityVector {
                        let dx: CGFloat
                        let dy: CGFloat
                    }
                
                    private let manager = CMMotionManager()
                    private let queue = OperationQueue()
                    private let gravitySubject = PassthroughSubject<GravityVector, Never>()
                
                    // Smoothed gravity using exponential moving average
                    private var emaX: Double = 0
                    private var emaY: Double = 0
                    private let alpha: Double = 0.15  // Low-pass factor
                    private let maxG: Double = 0.9   // Clamp extreme values
                
                    var gravityPublisher: AnyPublisher<GravityVector, Never> {
                        gravitySubject.eraseToAnyPublisher()
                    }
                
                    func startUpdates() {
                        guard manager.isDeviceMotionAvailable else { return }
                
                        manager.deviceMotionUpdateInterval = 1.0 / 60.0
                        queue.qualityOfService = .userInteractive
                
                        manager.startDeviceMotionUpdates(
                            using: .xArbitraryZVertical,
                            to: queue
                        ) { [weak self] motion, _ in
                            guard let self, let m = motion else { return }
                
                            // Apply low-pass filter
                            self.emaX = self.alpha * m.gravity.x + (1 - self.alpha) * self.emaX
                            self.emaY = self.alpha * m.gravity.y + (1 - self.alpha) * self.emaY
                
                            // Map to current interface orientation
                            let orientation = self.currentInterfaceOrientation()
                            let mapped = self.mapToInterface(
                                gx: self.emaX,
                                gy: self.emaY,
                                orientation: orientation
                            )
                
                            // Clamp and publish
                            let clamped = self.clamp(vector: mapped, max: self.maxG)
                            self.gravitySubject.send(
                                GravityVector(dx: CGFloat(clamped.dx), dy: CGFloat(clamped.dy))
                            )
                        }
                    }
                }
                """
                )

                BodyText("""
                The motion manager above uses a reference frame that combines gravity and magnetometer data for stable readings. \
                Low-pass filtering smooths jittery sensor data, while coordinate mapping ensures consistent behavior across device orientations.
                """)

                DividerLine()

                // Example 2 — Tilt Maze Game
                Subtitle("Example: Tilt Maze Physics Game")
                BodyText("""
                Combine CoreMotion with SpriteKit to create a physics-based tilt maze game. The game responds to device tilting \
                by applying gravity forces to a ball, creating intuitive tilt-to-move controls.
                """)

                CodeBlock(
                """
                final class TiltMazeGame: ObservableObject {
                    let scene: MazeScene
                    @Published private(set) var statusText: String = "Tilt to move the ball"
                
                    private let motion = MotionManager()
                    private var cancellables: Set<AnyCancellable> = []
                
                    init() {
                        scene = MazeScene(size: UIScreen.main.bounds.size)
                
                        // Bridge scene events to UI
                        scene.statePublisher
                            .receive(on: DispatchQueue.main)
                            .sink { [weak self] state in
                                self?.statusText = state.statusText
                            }
                            .store(in: &cancellables)
                
                        // Drive physics gravity from device motion
                        motion.gravityPublisher
                            .receive(on: DispatchQueue.main)
                            .sink { [weak scene] g in
                                scene?.applyGravity(g)
                            }
                            .store(in: &cancellables)
                    }
                
                    func start() {
                        scene.isPaused = false
                        motion.startUpdates()
                    }
                
                    func stop() {
                        scene.isPaused = true
                        motion.stopUpdates()
                    }
                }
                
                // SpriteKit scene that responds to gravity changes
                final class MazeScene: SKScene {
                    func applyGravity(_ g: MotionManager.GravityVector) {
                        // Map normalized device gravity to SpriteKit physics
                        physicsWorld.gravity = CGVector(
                            dx: g.dx * 9.8,  // SpriteKit gravity scale
                            dy: g.dy * 9.8
                        )
                    }
                }
                """
                )

                BodyText("""
                The tilt maze game creates an engaging experience by directly mapping device motion to physics simulation. \
                The ball rolls naturally in response to device tilting, creating intuitive controls that feel responsive and realistic.
                """)

                DividerLine()

                // Example 3 — Coordinate Mapping
                Subtitle("Example: Device Orientation Handling")
                BodyText("""
                Handle device orientation changes by mapping gravity coordinates appropriately. This ensures consistent \
                tilt behavior whether the device is held in portrait, landscape, or upside-down orientations.
                """)

                CodeBlock(
                """
                private func mapToInterface(
                    gx: Double,
                    gy: Double,
                    orientation: UIInterfaceOrientation
                ) -> (dx: Double, dy: Double) {
                    // SpriteKit's positive Y is up
                    // We want tilting top-down to push the ball down
                    switch orientation {
                        case .portrait:
                            return (dx: gx, dy: gy)
                        case .portraitUpsideDown:
                            return (dx: -gx, dy: -gy)
                        case .landscapeLeft:
                            return (dx: -gy, dy: gx)
                        case .landscapeRight:
                            return (dx: gy, dy: -gx)
                        default:
                            return (dx: gx, dy: gy)
                    }
                }
                
                private func clamp(
                    vector: (dx: Double, dy: Double),
                    max: Double
                ) -> (dx: Double, dy: Double) {
                    let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
                    guard magnitude > max, magnitude > 0 else { return vector }
                    let scale = max / magnitude
                    return (dx: vector.dx * scale, dy: vector.dy * scale)
                }
                """
                )

                BodyText("""
                Proper coordinate mapping ensures your tilt controls work intuitively regardless of how the user holds their device. \
                Clamping prevents extreme sensor readings from creating unplayable game mechanics.
                """)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("CoreMotion")
        .navigationBarTitleDisplayMode(.inline)
    }
}