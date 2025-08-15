import Foundation
import NaturalLanguage

/// A minimal, dependency-free sentiment analyzer built on top of
/// Apple’s `NaturalLanguage` framework.
///
/// It maps `NLTagger`'s `.sentimentScore` values (−1.0…+1.0) to a
/// human-friendly label ("Positive", "Neutral", "Negative") and a
/// confidence value in the 0…1 range.
///
/// - Important: This implementation does **not** use any `.mlmodel` and
///   runs fully on-device via `NaturalLanguage`.
final class TextSentimentAnalyzer {

    /// Serial queue used to perform NLP work off the main thread.
    private let queue: DispatchQueue = DispatchQueue(label: "nl.sentiment.queue")

    /// Positive decision threshold used when mapping the calibrated score to a label.
    private let positiveThreshold: Double = 0.25
    /// Negative decision threshold used when mapping the calibrated score to a label.
    private let negativeThreshold: Double = -0.25

    /// Classifies raw text into `Positive`, `Neutral`, or `Negative`.
    ///
    /// The pipeline:
    /// 1. Detect dominant language (fallback to English).
    /// 2. Use `NLTagger` to compute per-sentence sentiment and average.
    /// 3. Calibrate with simple lexical hints and intensifier overrides (no length damping).
    /// 4. Map the score to a label with fixed thresholds and derive a confidence (0…1).
    ///
    /// - Parameters:
    ///   - text: The input text to analyze.
    ///   - completion: Invoked on the main thread with the resulting label and confidence.
    func classify(
        text: String,
        completion: @escaping (_ label: String, _ confidence: Double) -> Void
    ) {
        queue.async {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                DispatchQueue.main.async { completion("Neutral", 0.0) }
                return
            }

            let langRecognizer = NLLanguageRecognizer()
            langRecognizer.processString(trimmed)
            let dominant = langRecognizer.dominantLanguage
            let nlLanguage: NLLanguage = dominant ?? .english

            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            tagger.string = trimmed
            let fullRange = trimmed.startIndex..<trimmed.endIndex
            tagger.setLanguage(nlLanguage, range: fullRange)

            var sum: Double = 0
            var count: Int = 0
            tagger.enumerateTags(
                in: fullRange,
                unit: .sentence,
                scheme: .sentimentScore,
                options: [.omitWhitespace, .omitPunctuation]
            ) { tag, range in
                if let raw = tag?.rawValue, let v = Double(raw) {
                    sum += v
                    count += 1
                } else {
                    sum += 0
                    count += 1
                }
                return true
            }

            let baseScore: Double
            if count > 0 {
                baseScore = sum / Double(count)
            } else if let raw = tagger.tag(
                at: fullRange.lowerBound,
                unit: .paragraph,
                scheme: .sentimentScore
            ).0?.rawValue, let v = Double(raw) {
                baseScore = v
            } else {
                baseScore = 0
            }

            let lower = trimmed.lowercased()

            var boost: Double = 0
            let hasNegator = lower.contains("not ") || lower.contains("n't ")
            if !hasNegator {
                if lower.contains(" ok") || lower.hasPrefix("ok") || lower.contains(" okay") { boost += 0.06 }
                if lower.contains(" fine") || lower.hasPrefix("fine") { boost += 0.06 }
                if lower.contains(" alright") || lower.hasPrefix("alright") { boost += 0.04 }
            }

            let hasIntensifier = lower.contains("very ") || lower.contains("super ") || lower.contains("really ")
            let positiveLex = ["good","great","amazing","awesome","fantastic","love","excellent","happy","perfect"]
            let negativeLex = ["bad","terrible","awful","hate","horrible","worst","sad","poor"]

            func containsAny(_ terms: [String], in text: String) -> Bool {
                for t in terms { if text.contains(" " + t) || text.hasPrefix(t) { return true } }
                return false
            }

            var calibrated: Double = baseScore + boost
            var usedIntensityOverride = false
            if !hasNegator && containsAny(positiveLex, in: lower) {
                usedIntensityOverride = hasIntensifier || trimmed.count <= 20
                if usedIntensityOverride {
                    calibrated = 1.0
                } else {
                    calibrated = min(1.0, calibrated + (hasIntensifier ? 0.5 : 0.3))
                }
            } else if containsAny(negativeLex, in: lower) {
                usedIntensityOverride = hasIntensifier || trimmed.count <= 20
                if usedIntensityOverride {
                    calibrated = -1.0
                } else {
                    calibrated = max(-1.0, calibrated - (hasIntensifier ? 0.5 : 0.3))
                }
            }

            let positiveThreshold: Double = 0.10
            let negativeThreshold: Double = -0.10

            let label: String
            if calibrated >= positiveThreshold {
                label = "Positive"
            } else if calibrated <= negativeThreshold {
                label = "Negative"
            } else {
                label = "Neutral"
            }

            let clamped = max(-1.0, min(1.0, calibrated))
            var confidence = min(1.0, pow(abs(clamped), 0.6))
            if usedIntensityOverride && abs(clamped) >= 0.9 { confidence = 1.0 }

            DispatchQueue.main.async {
                completion(label, confidence)
            }
        }
    }
}
