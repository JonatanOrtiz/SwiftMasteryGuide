//
//  TiltMazeDemoView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 08/09/25.
//

import SwiftUI
import SpriteKit
import CoreMotion
import Combine
import UIKit

// MARK: - Public SwiftUI Entry

struct TiltMazeDemoView: View {
    @StateObject private var game = TiltMazeGame()

    var body: some View {
        ZStack {
            // SpriteKit scene
            SpriteView(
                scene: game.scene,
                options:
                    [
                        .ignoresSiblingOrder,
                        .shouldCullNonVisibleNodes
                    ]
            )
            .ignoresSafeArea()
            .accessibilityLabel("Tilt maze game")

            // HUD
            VStack(spacing: 12) {
                HStack {
                    Text(game.statusText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.cardBackground.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dividerColor, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Game status")

                    Spacer()

                    Button(
                        action: { game.resetLevel() },
                        label: {
                            Text("Reset")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    )
                    .accessibilityLabel("Reset game")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
    }
}

// MARK: - Game orchestrator (ObservableObject)

final class TiltMazeGame: ObservableObject {
    // Exposed scene to SwiftUI SpriteView
    let scene: MazeScene

    @Published private(set) var statusText: String = "Tilt to move the ball"

    private let motion = MotionManager()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        scene = MazeScene(
            size: UIScreen.main.bounds.size
        )

        // Bridge scene events back to UI text
        scene.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.statusText = state.statusText
            }
            .store(in: &cancellables)

        // Drive gravity from device motion
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

    func resetLevel() {
        scene.reset()
    }
}

// MARK: - Motion manager (low-pass + orientation aware)

final class MotionManager {
    struct GravityVector {
        let dx: CGFloat
        let dy: CGFloat
    }

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let gravitySubject = PassthroughSubject<GravityVector, Never>()

    /// Smoothed gravity (low-pass)
    private var emaX: Double = 0
    private var emaY: Double = 0

    /// Low-pass factor (higher = smoother, slower)
    private let alpha: Double = 0.15

    /// Clamp to avoid extreme slopes creating runaway speeds
    private let maxG: Double = 0.9

    var gravityPublisher: AnyPublisher<GravityVector, Never> {
        gravitySubject.eraseToAnyPublisher()
    }

    func startUpdates() {
        guard manager.isDeviceMotionAvailable else { return }

        // Use reference frame that combines gravity + magnetometer for stable heading, if available.
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        queue.qualityOfService = .userInteractive

        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, _ in
            guard
                let self,
                let m = motion
            else { return }

            // Raw gravity in device coordinates
            let gx = m.gravity.x
            let gy = m.gravity.y

            // Smooth (EMA)
            self.emaX = self.alpha * gx + (1 - self.alpha) * self.emaX
            self.emaY = self.alpha * gy + (1 - self.alpha) * self.emaY

            // Map to UI orientation
            let orientation = Self.currentInterfaceOrientation()
            let mapped = Self.mapToInterface(
                gx: self.emaX,
                gy: self.emaY,
                orientation: orientation
            )

            // Clamp magnitude
            let clamped = Self.clamp(vector: mapped, max: self.maxG)

            self.gravitySubject.send(
                GravityVector(
                    dx: CGFloat(clamped.dx),
                    dy: CGFloat(clamped.dy)
                )
            )
        }
    }

    func stopUpdates() {
        manager.stopDeviceMotionUpdates()
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let o = scenes.first?.interfaceOrientation {
            return o
        }
        // Fallback
        return .portrait
    }

    private static func mapToInterface(
        gx: Double,
        gy: Double,
        orientation: UIInterfaceOrientation
    ) -> (dx: Double, dy: Double) {
        // SpriteKit's positive Y is up. We want tilting top-down to push the ball down.
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

    private static func clamp(
        vector: (dx: Double, dy: Double),
        max: Double
    ) -> (dx: Double, dy: Double) {
        let mag = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard mag > max, mag > 0 else { return vector }
        let scale = max / mag
        return (dx: vector.dx * scale, dy: vector.dy * scale)
    }
}

// MARK: - Scene state

enum MazeGameState: Equatable {
    case playing
    case won
    case lost

    var statusText: String {
        switch self {
            case .playing:
                return "Tilt to move the ball"
            case .won:
                return "Great! You reached the goal 🎉"
            case .lost:
                return "Oops! Out of bounds"
        }
    }
}

// MARK: - SpriteKit scene

final class MazeScene: SKScene, SKPhysicsContactDelegate {

    // Publishers
    private let stateSubject = CurrentValueSubject<MazeGameState, Never>(.playing)
    var statePublisher: AnyPublisher<MazeGameState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // Nodes
    private var ball: SKShapeNode?
    private var goal: SKShapeNode?
    private var boundary: SKShapeNode?

    // Layout cache
    private var contentInset: CGFloat = 24
    private var playableRect: CGRect = .zero

    // Physics categories
    private struct Category {
        static let none: UInt32     = 0
        static let ball: UInt32     = 1 << 0
        static let wall: UInt32     = 1 << 1
        static let goal: UInt32     = 1 << 2
        static let edge: UInt32     = 1 << 3
        static let hazard: UInt32   = 1 << 4
    }

    // Tuning
    private struct Tuning {
        static let ballRadius: CGFloat = 14
        static let ballRestitution: CGFloat = 0.2
        static let ballLinearDamping: CGFloat = 0.45
        static let ballAngularDamping: CGFloat = 0.3
        static let ballFriction: CGFloat = 0.5

        static let gravityScale: CGFloat = 9.8 // SpriteKit expects m/s^2-ish

        static let wallThickness: CGFloat = 10
        static let goalRadius: CGFloat = 18
    }

    // MARK: Init

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor.systemBackground

        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
        physicsWorld.speed = 1.0

        setUpSceneGraph()
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.isMultipleTouchEnabled = false

        // Redraw on size changes (rotation)
        layoutForCurrentSize()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutForCurrentSize()
    }

    // MARK: Public controls

    func applyGravity(_ g: MotionManager.GravityVector) {
        // Map normalized device gravity [-1, 1] to SpriteKit gravity
        physicsWorld.gravity = CGVector(
            dx: g.dx * Tuning.gravityScale,
            dy: g.dy * Tuning.gravityScale
        )
    }

    func reset() {
        stateSubject.send(.playing)
        removeAllActions()
        removeAllChildren()
        setUpSceneGraph()
        layoutForCurrentSize()
    }

    // MARK: Build scene

    private func setUpSceneGraph() {
        // Edge boundary (playable area)
        let inset = contentInset
        playableRect = frame.insetBy(
            dx: inset,
            dy: inset
        )

        boundary = SKShapeNode(rect: playableRect)
        boundary?.strokeColor = UIColor.separator
        boundary?.lineWidth = 2
        if let boundary {
            addChild(boundary)
        }

        physicsBody = SKPhysicsBody(edgeLoopFrom: playableRect)
        physicsBody?.categoryBitMask = Category.edge
        physicsBody?.contactTestBitMask = Category.ball
        physicsBody?.collisionBitMask = Category.ball

        // Maze walls
        buildMazeWalls(in: playableRect)

        // Goal
        let goalNode = SKShapeNode(circleOfRadius: Tuning.goalRadius)
        goalNode.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
        goalNode.strokeColor = UIColor.systemGreen
        goalNode.lineWidth = 2
        goalNode.name = "goal"

        // Temporarily position; will be placed in layout
        goalNode.position = .zero
        goalNode.physicsBody = SKPhysicsBody(circleOfRadius: Tuning.goalRadius)
        goalNode.physicsBody?.isDynamic = false
        goalNode.physicsBody?.categoryBitMask = Category.goal
        goalNode.physicsBody?.contactTestBitMask = Category.ball
        goalNode.physicsBody?.collisionBitMask = Category.none
        addChild(goalNode)
        goal = goalNode

        // Ball
        let ballNode = SKShapeNode(circleOfRadius: Tuning.ballRadius)
        ballNode.fillColor = UIColor.systemBlue
        ballNode.strokeColor = UIColor.systemBlue.withAlphaComponent(0.3)
        ballNode.lineWidth = 2
        ballNode.name = "ball"

        let body = SKPhysicsBody(circleOfRadius: Tuning.ballRadius)
        body.affectedByGravity = true
        body.allowsRotation = true
        body.isDynamic = true
        body.mass = 0.04
        body.restitution = Tuning.ballRestitution
        body.linearDamping = Tuning.ballLinearDamping
        body.angularDamping = Tuning.ballAngularDamping
        body.friction = Tuning.ballFriction
        body.categoryBitMask = Category.ball
        body.contactTestBitMask = Category.goal | Category.hazard | Category.edge
        body.collisionBitMask = Category.wall | Category.edge
        ballNode.physicsBody = body

        addChild(ballNode)
        ball = ballNode
    }

    private func layoutForCurrentSize() {
        // Update playable rect after rotations / size changes
        playableRect = frame.insetBy(
            dx: contentInset,
            dy: contentInset
        )
        boundary?.path = UIBezierPath(rect: playableRect).cgPath
        physicsBody = SKPhysicsBody(edgeLoopFrom: playableRect)
        physicsBody?.categoryBitMask = Category.edge
        physicsBody?.contactTestBitMask = Category.ball
        physicsBody?.collisionBitMask = Category.ball

        // Place ball and goal at deterministic spots within the maze
        let start = CGPoint(
            x: playableRect.minX + 40,
            y: playableRect.maxY - 40
        )
        ball?.position = start

        let end = CGPoint(
            x: playableRect.maxX - 40,
            y: playableRect.minY + 40
        )
        goal?.position = end
    }

    // MARK: Walls / Maze

    private func buildMazeWalls(in rect: CGRect) {
        // Simple, readable “S” shaped path using segments.
        // All walls are static physics bodies.
        let t = Tuning.wallThickness

        func addWall(_ r: CGRect) {
            let node = SKShapeNode(rect: r)
            node.fillColor = UIColor.secondaryLabel.withAlphaComponent(0.15)
            node.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.35)
            node.lineWidth = 1

            node.physicsBody = SKPhysicsBody(edgeLoopFrom: r)
            node.physicsBody?.isDynamic = false
            node.physicsBody?.categoryBitMask = Category.wall
            node.physicsBody?.contactTestBitMask = Category.ball
            node.physicsBody?.collisionBitMask = Category.ball

            addChild(node)
        }

        // Horizontal bands
        let band1 = CGRect(
            x: rect.minX + 20,
            y: rect.midY + 70,
            width: rect.width - 40,
            height: t
        )
        addWall(band1)

        let band2 = CGRect(
            x: rect.minX + 20,
            y: rect.midY,
            width: rect.width - 120,
            height: t
        )
        addWall(band2)

        let band3 = CGRect(
            x: rect.minX + 100,
            y: rect.midY - 70,
            width: rect.width - 120,
            height: t
        )
        addWall(band3)

        // Vertical pillars
        let pillar1 = CGRect(
            x: rect.midX - 80,
            y: rect.midY - 70,
            width: t,
            height: 140
        )
        addWall(pillar1)

        let pillar2 = CGRect(
            x: rect.midX + 60,
            y: rect.midY - 140,
            width: t,
            height: 140
        )
        addWall(pillar2)

        // Optional hazards (holes) – small circles that “reset” the ball
        addHazard(
            center: CGPoint(
                x: rect.midX - 20,
                y: rect.midY + 30
            ),
            radius: 12
        )
        addHazard(
            center: CGPoint(
                x: rect.midX + 40,
                y: rect.midY - 30
            ),
            radius: 12
        )
    }

    private func addHazard(
        center: CGPoint,
        radius: CGFloat
    ) {
        let hole = SKShapeNode(circleOfRadius: radius)
        hole.position = center
        hole.fillColor = UIColor.systemRed.withAlphaComponent(0.18)
        hole.strokeColor = UIColor.systemRed
        hole.lineWidth = 1
        hole.name = "hazard"

        hole.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        hole.physicsBody?.isDynamic = false
        hole.physicsBody?.categoryBitMask = Category.hazard
        hole.physicsBody?.contactTestBitMask = Category.ball
        hole.physicsBody?.collisionBitMask = Category.none

        addChild(hole)
    }

    // MARK: Contacts

    func didBegin(
        _ contact: SKPhysicsContact
    ) {
        guard
            let a = contact.bodyA.node,
            let b = contact.bodyB.node
        else { return }

        let names = [a.name ?? "", b.name ?? ""]

        if names.contains("ball"), names.contains("goal") {
            handleWin()
            return
        }

        if names.contains("ball"), names.contains("hazard") {
            handleLoss()
            return
        }
    }

    private func handleWin() {
        guard stateSubject.value == .playing else { return }
        stateSubject.send(.won)

        // Celebrate: scale + fade ball into goal, then bounce text
        let duration: TimeInterval = 0.35
        ball?.run(
            .group(
                [
                    .scale(to: 0.1, duration: duration),
                    .fadeOut(withDuration: duration)
                ]
            )
        )

        run(
            .sequence(
                [
                    .wait(forDuration: duration),
                    .run { [weak self] in
                        self?.showCenteredLabel(
                            text: "You Win!",
                            color: UIColor.systemGreen
                        )
                    }
                ]
            )
        )
    }

    private func handleLoss() {
        guard stateSubject.value == .playing else { return }
        stateSubject.send(.lost)

        ball?.physicsBody?.velocity = .zero
        let start = CGPoint(
            x: playableRect.minX + 40,
            y: playableRect.maxY - 40
        )

        let shake = SKAction.sequence(
            [
                .moveBy(x: -6, y: 0, duration: 0.05),
                .moveBy(x: 12, y: 0, duration: 0.08),
                .moveBy(x: -6, y: 0, duration: 0.05)
            ]
        )
        ball?.run(shake)

        run(
            .sequence(
                [
                    .wait(forDuration: 0.25),
                    .run { [weak self] in
                        self?.ball?.position = start
                        self?.ball?.setScale(1)
                        self?.ball?.alpha = 1
                        self?.stateSubject.send(.playing)
                    }
                ]
            )
        )
    }

    // MARK: Helpers

    private func showCenteredLabel(
        text: String,
        color: UIColor
    ) {
        let label = SKLabelNode(text: text)
        label.fontName = UIFont.preferredFont(forTextStyle: .largeTitle).fontName
        label.fontSize = 44
        label.fontColor = color
        label.position = CGPoint(x: frame.midX, y: frame.midY)
        label.alpha = 0
        addChild(label)

        label.run(
            .sequence(
                [
                    .fadeIn(withDuration: 0.22),
                    .scale(by: 1.08, duration: 0.22),
                    .wait(forDuration: 0.6),
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent()
                ]
            )
        )
    }
}
