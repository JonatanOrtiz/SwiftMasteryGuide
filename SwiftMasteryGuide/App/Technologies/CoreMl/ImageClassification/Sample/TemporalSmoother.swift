//
//  TemporalSmoother.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 12/08/25.
//

/// Simple temporal smoothing: EMA for confidence + label “lock” for brief stability.
final class TemporalSmoother {
    private var lastStableLabel: String?
    private var stableFrameCount = 0
    private var exponentialMovingAverage: Float = 0
    private let alpha: Float = 0.30
    private let framesRequiredForLock = 3

    func update(label: String, confidence: Float) -> (label: String, confidence: Float) {
        exponentialMovingAverage = exponentialMovingAverage == 0
        ? confidence
        : (alpha * confidence + (1 - alpha) * exponentialMovingAverage)

        if label == lastStableLabel {
            stableFrameCount += 1
        } else {
            lastStableLabel = label
            stableFrameCount = 1
        }
        let lockedLabel = (stableFrameCount >= framesRequiredForLock) ? label : (lastStableLabel ?? label)
        return (lockedLabel, exponentialMovingAverage)
    }
}
