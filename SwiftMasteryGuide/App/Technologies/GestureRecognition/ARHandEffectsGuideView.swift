//
//  ARHandEffectsGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 21/08/25.
//

import SwiftUI
import Vision

struct ARHandEffectsGuideView: View {

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Lesson Intro
                Title("Hand Gesture Recognition – Overview")
                BodyText("""
                Hand gesture recognition uses Apple's Vision framework to detect and track human hand poses in real-time. \
                You can identify specific gestures like open palm, victory sign, and create interactive visual effects that respond to hand movements.
                """)

                DividerLine()

                // Learning goals
                Subtitle("What You Will Learn")
                BulletList([
                    "How to use Vision framework for real-time hand pose detection.",
                    "How to analyze hand landmarks and finger positions.",
                    "How to detect specific gestures like open palm and victory sign.",
                    "How to create particle effects that respond to hand gestures."
                ])

                DividerLine()

                // Example 1 — Basic hand detection
                Subtitle("Example: Basic Hand Pose Detection")
                BodyText("""
                Use `VNDetectHumanHandPoseRequest` to detect hands in camera frames. \
                The Vision framework provides detailed landmark points for fingers, wrist, and palm.
                """)

                CodeBlock(
                """
                import Vision
                import AVFoundation

                class HandDetectionViewController: UIViewController {
                    private var handPoseRequest = VNDetectHumanHandPoseRequest()
                    private let visionQueue = DispatchQueue(label: "vision.handpose.queue")
                    
                    func processFrame(_ pixelBuffer: CVPixelBuffer) {
                        let request = handPoseRequest
                        request.maximumHandCount = 1
                        
                        visionQueue.async {
                            do {
                                let handler = VNImageRequestHandler(
                                    cvPixelBuffer: pixelBuffer,
                                    orientation: .leftMirrored,
                                    options: [:]
                                )
                                try handler.perform([request])
                                
                                guard let observations = request.results,
                                      !observations.isEmpty else { return }
                                
                                let bestHand = observations.max(by: { $0.confidence < $1.confidence })
                                if let hand = bestHand {
                                    self.analyzeHand(hand)
                                }
                            } catch {
                                print("Hand detection failed: \\(error)")
                            }
                        }
                    }
                    
                    private func analyzeHand(_ observation: VNHumanHandPoseObservation) {
                        do {
                            let points = try observation.recognizedPoints(.all)
                            
                            // Extract key landmarks
                            if let wrist = points[.wrist],
                               let indexTip = points[.indexTip],
                               let thumbTip = points[.thumbTip] {
                                
                                print("Wrist: \\(wrist.location)")
                                print("Index tip: \\(indexTip.location)")
                                print("Thumb tip: \\(thumbTip.location)")
                            }
                        } catch {
                            print("Failed to extract hand points: \\(error)")
                        }
                    }
                }
                """
                )

                BodyText("""
                The code above shows basic hand detection setup. Vision provides normalized coordinates (0-1) for all hand landmarks, \
                making it easy to work with different screen sizes and camera orientations.
                """)

                DividerLine()

                // Example 2 — Gesture recognition
                Subtitle("Example: Gesture Recognition Logic")
                BodyText("""
                Analyze finger positions relative to palm and wrist to detect specific gestures. \
                Each gesture has unique characteristics in terms of finger extension and spatial relationships.
                """)

                CodeBlock(
                """
                struct HandGestureAnalyzer {
                    
                    static func detectGesture(from observation: VNHumanHandPoseObservation) -> HandGesture? {
                        do {
                            let points = try observation.recognizedPoints(.all)
                            
                            guard let wrist = points[.wrist]?.location else { return nil }
                            
                            // Define finger data structure
                            struct Finger {
                                let tip: CGPoint?
                                let mcp: CGPoint? // Metacarpophalangeal joint (knuckle)
                            }
                            
                            let fingers: [Finger] = [
                                Finger(tip: points[.thumbTip]?.location, mcp: points[.thumbCMC]?.location),
                                Finger(tip: points[.indexTip]?.location, mcp: points[.indexMCP]?.location),
                                Finger(tip: points[.middleTip]?.location, mcp: points[.middleMCP]?.location),
                                Finger(tip: points[.ringTip]?.location, mcp: points[.ringMCP]?.location),
                                Finger(tip: points[.littleTip]?.location, mcp: points[.littleMCP]?.location)
                            ]
                            
                            // Analyze which fingers are extended
                            var extendedFingers: [Int] = []
                            
                            for (index, finger) in fingers.enumerated() {
                                guard let tip = finger.tip, let mcp = finger.mcp else { continue }
                                
                                let tipToMcpDistance = distance(from: tip, to: mcp)
                                let tipToWristDistance = distance(from: tip, to: wrist)
                                
                                // Finger is considered extended if it's far from both MCP and wrist
                                let isExtended = tipToWristDistance > 0.16 && tipToMcpDistance > 0.08
                                
                                if isExtended {
                                    extendedFingers.append(index)
                                }
                            }
                            
                            // Detect specific gestures
                            return classifyGesture(extendedFingers: extendedFingers)
                            
                        } catch {
                            return nil
                        }
                    }
                    
                    private static func classifyGesture(extendedFingers: [Int]) -> HandGesture {
                        switch extendedFingers.count {
                        case 0, 1:
                            return .fist
                        case 2:
                            if extendedFingers.contains(1) && extendedFingers.contains(2) {
                                return .victory // Index and middle finger
                            }
                            return .partial
                        case 3, 4, 5:
                            return .openPalm
                        default:
                            return .unknown
                        }
                    }
                    
                    private static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
                        return hypot(point1.x - point2.x, point1.y - point2.y)
                    }
                }

                enum HandGesture {
                    case fist
                    case victory
                    case openPalm
                    case partial
                    case unknown
                }
                """
                )

                BodyText("""
                This analyzer calculates distances between finger tips, knuckles, and wrist to determine finger extension. \
                Different gesture patterns can trigger different visual effects or app behaviors.
                """)

                DividerLine()

                // Example 3 — Particle effects
                Subtitle("Example: Gesture-Triggered Particle Effects")
                BodyText("""
                Create engaging visual feedback using Core Animation's particle system that responds to detected gestures. \
                Different gestures can trigger different types of effects.
                """)

                CodeBlock(
                """
                import UIKit
                import QuartzCore

                class GestureEffectsView: UIView {
                    private let bubbleEmitter = CAEmitterLayer()
                    private let sparkEmitter = CAEmitterLayer()
                    
                    override init(frame: CGRect) {
                        super.init(frame: frame)
                        setupEmitters()
                    }
                    
                    required init?(coder: NSCoder) {
                        super.init(coder: coder)
                        setupEmitters()
                    }
                    
                    private func setupEmitters() {
                        // Bubble emitter for open palm
                        bubbleEmitter.emitterShape = .point
                        bubbleEmitter.emitterMode = .points
                        bubbleEmitter.renderMode = .additive
                        bubbleEmitter.birthRate = 0 // Start disabled
                        
                        let bubbleCell = CAEmitterCell()
                        bubbleCell.contents = createBubbleImage()?.cgImage
                        bubbleCell.birthRate = 35
                        bubbleCell.lifetime = 2.8
                        bubbleCell.velocity = 120
                        bubbleCell.scale = 0.06
                        bubbleCell.alphaSpeed = -0.4
                        bubbleCell.emissionRange = .pi * 2
                        
                        bubbleEmitter.emitterCells = [bubbleCell]
                        layer.addSublayer(bubbleEmitter)
                        
                        // Spark emitter for victory sign
                        sparkEmitter.emitterShape = .point
                        sparkEmitter.renderMode = .additive
                        sparkEmitter.birthRate = 0 // Start disabled
                        
                        let sparkCell = CAEmitterCell()
                        sparkCell.contents = createSparkImage()?.cgImage
                        sparkCell.birthRate = 150
                        sparkCell.lifetime = 0.4
                        sparkCell.velocity = 180
                        sparkCell.scale = 0.05
                        sparkCell.alphaSpeed = -1.0
                        sparkCell.emissionRange = .pi * 2
                        
                        sparkEmitter.emitterCells = [sparkCell]
                        layer.addSublayer(sparkEmitter)
                    }
                    
                    func triggerBubbles(at position: CGPoint) {
                        bubbleEmitter.emitterPosition = position
                        bubbleEmitter.birthRate = 1.0
                    }
                    
                    func stopBubbles() {
                        bubbleEmitter.birthRate = 0.0
                    }
                    
                    func triggerSparks(at position: CGPoint) {
                        sparkEmitter.emitterPosition = position
                        sparkEmitter.birthRate = 1.0
                        
                        // Auto-stop sparks after brief burst
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.sparkEmitter.birthRate = 0.0
                        }
                    }
                    
                    private func createBubbleImage() -> UIImage? {
                        let size = CGSize(width: 20, height: 20)
                        return UIGraphicsImageRenderer(size: size).image { context in
                            let rect = CGRect(origin: .zero, size: size)
                            UIColor.white.withAlphaComponent(0.8).setFill()
                            UIBezierPath(ovalIn: rect).fill()
                        }
                    }
                    
                    private func createSparkImage() -> UIImage? {
                        let size = CGSize(width: 10, height: 10)
                        return UIGraphicsImageRenderer(size: size).image { context in
                            let rect = CGRect(origin: .zero, size: size)
                            UIColor.yellow.setFill()
                            UIBezierPath(ovalIn: rect).fill()
                        }
                    }
                }
                """
                )

                BodyText("""
                The effects system above creates different particle animations for different gestures. \
                Open palm triggers continuous bubbles, while victory sign creates a brief spark burst.
                """)

                DividerLine()

                // Demo section
                Subtitle("Try It In The App")
                BodyText("""
                Test the hand gesture recognition demo below. Hold your hand in front of the camera and try different gestures:
                • Open palm: Triggers continuous bubble effects
                • Victory sign (✌️): Creates spark burst effects
                """)

                HStack(spacing: 12) {
                    NavigationLink(
                        destination: ARHandEffectsDemoView()
                    ) {
                        Text("Open Hand Effects Demo")
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Open hand effects demo")
                }
            }
            .padding(20)
        }
        .navigationTitle("Hand Gesture Recognition")
        .navigationBarTitleDisplayMode(.inline)
    }
}
