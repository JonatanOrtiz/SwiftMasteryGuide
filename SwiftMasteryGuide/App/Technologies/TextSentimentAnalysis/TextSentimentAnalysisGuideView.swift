import SwiftUI

/// Guide screen that explains, step by step, how our Text Sentiment is implemented.
struct TextSentimentAnalysisGuideView: View {

    // Examples that move from negative -> positive
    private let progressionExamples: [String] = [
        // Negative -> less negative
        "I didn’t like this at all.\nIt felt slow and frustrating.",
        // Neutral / mild
        "Then, it started to work better.\nSome features became useful.",
        // Moderate positive
        "I felt comfortable using it.\nNow, it’s smooth and easy.",
        // Strong positive
        "I enjoy it a lot.\nIt’s one of my favorite tools.",
        // Short emphasis that should saturate
        "very happy",
    ]

    // Quick unit cases to check calibration (short/emphatic/negation)
    private let quickChecks: [String] = [
        "very happy",
        "really awful",
        "super amazing",
        "not good",
        "not bad",
        "ok",
        "fine",
        "alright",
        "I love this",
        "I hate this",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                NavigationLink(destination: TextSentimentAnalysisView()) {
                    Text("Open Text Sentiment Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open text sentiment analysis demo")

                Title("Text Sentiment – Guide")

                BodyText("""
This guide teaches how to implement the exact pipeline used in the app:
NLTagger-based per-sentence scoring, calibration without length damping,
intensity overrides for emphatic short phrases, and threshold/confidence mapping.
""")

                // --- Pipeline overview (short) ---
                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("How it Works (Pipeline)")
                    BodyText("• Detect dominant language (fallback to English).\n• Sentence-level sentiment with `NLTagger(.sentimentScore)` and average.\n• Calibration **without length damping**.\n• **Intensity override** for emphatic short phrases (e.g., “very happy”, “really awful”).\n• Map calibrated score → **Positive / Neutral / Negative** with looser thresholds (±0.10).\n• Compute confidence with a curve that emphasizes extremes and saturates on overrides.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Why It Feels Better Now")
                    BodyText("• Short texts (e.g., “very happy”) no longer stick near neutral.\n• Emphatic phrases can **saturate** (±1.0) and yield **100% confidence**.\n• Slightly looser thresholds help positive sentiment appear earlier as the text improves.")
                }

                // --- Step-by-step implementation with exact code ---
                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 1 — Language Detection (NaturalLanguage)")
                    BodyText("Detect the dominant language and set it on the tagger to keep scoring consistent.")
                    CodeBlock(#"""
import NaturalLanguage

let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
let langRecognizer = NLLanguageRecognizer()
langRecognizer.processString(trimmed)
let dominant = langRecognizer.dominantLanguage
let nlLanguage: NLLanguage = dominant ?? .english
"""#)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 2 — Configure NLTagger and Score Per Sentence")
                    BodyText("Create an `NLTagger` for `.sentimentScore`, set the language, then average sentence scores.")
                    CodeBlock(#"""
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
) { tag, _ in
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
"""#)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 3 — Calibration (No Length Damping) + Intensity Override")
                    BodyText("Apply small lexical boosts for mild positives (without negation) and saturate short/emphatic phrases.")
                    CodeBlock(#"""
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
"""#)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 4 — Thresholds and Confidence")
                    BodyText("Map the calibrated score to a label and compute confidence with a curve that emphasizes extremes.")
                    CodeBlock(#"""
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
"""#)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 5 — Full Usage Example")
                    BodyText("Using the analyzer from UI code.")
                    CodeBlock(#"""
let analyzer = TextSentimentAnalyzer()
analyzer.classify(text: "I love how easy this app makes learning iOS.") { label, confidence in
    print("Label:", label)                // e.g., "Positive"
    print("Confidence:", confidence)      // e.g., 0.92
}
"""#)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Step 6 — ViewModel Integration (Debounce + Bindings)")
                    BodyText("Hook the analyzer into a debounced ViewModel that drives the UI.")
                    CodeBlock(#"""
final class TextSentimentAnalysisViewModel: ObservableObject {
    @Published var inputText: String = "" { didSet { scheduleClassification() } }
    @Published var resultLabel: String = "—"
    @Published var confidenceText: String = "—"

    var resultSummary: String { "\(resultLabel)  •  \(confidenceText)" }

    private let analyzer: TextSentimentAnalyzer? = TextSentimentAnalyzer()
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.25

    func classifyNow() {
        runClassification(for: inputText)
    }

    private func scheduleClassification() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.runClassification(for: self.inputText)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func runClassification(for text: String) {
        guard let analyzer = analyzer else {
            resultLabel = "Model not available"
            confidenceText = ""
            return
        }
        analyzer.classify(text: text) { [weak self] label, conf in
            guard let self = self else { return }
            self.resultLabel = label.capitalized
            self.confidenceText = String(format: "%.0f%%", conf * 100)
        }
    }
}
"""#)
                }

                // --- Hands-on: copy and test in the live view ---
                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Try a Gradual Progression")
                    BodyText("Type step by step; the score should move from negative → positive.")
                    CodeBlock(progressionExamples.joined(separator: "\n\n"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Quick Checks (Unit-style)")
                    BodyText("Short emphatic phrases should saturate; negations should flip meaning.")
                    CodeBlock(quickChecks.joined(separator: "\n"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Tips & Pitfalls")
                    BodyText("• Mixed sentences (e.g., “Great idea, but poor execution.”) can average out.\n• Negations like “not good / not bad” are tricky; test both.\n• Language matters: NL auto-detects, but domain-specific expressions may require a custom Core ML model (e.g., BERT).")
                }
            }
            .padding(20)
        }
        .navigationTitle("Sentiment Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
