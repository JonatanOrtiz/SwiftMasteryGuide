//
//  SpeechToTextGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 13/08/25.
//

import SwiftUI

/// A step-by-step guide that explains how this feature works:
/// - We load Whisper (ggml) and its Core ML encoder from the app bundle.
/// - We capture microphone audio via `AVAudioEngine`.
/// - We always normalize to 16 kHz, mono, Float32 (downmix + resample if needed).
/// - We accumulate frames into a sliding window and trigger streaming transcription.
/// - We publish the decoded text to SwiftUI.
///
/// All code inside the app is written in English to match documentation
/// (Medium article + in-app guide). Every code block below indicates
/// the **file** and **section** where it belongs.
struct SpeechToTextGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Intro

                Title("Speech-to-Text with Whisper + Core ML (On-Device)")
                BodyText(
                    """
                    In this lesson you will learn how to perform real-time speech-to-text \
                    fully on-device using Whisper (ggml) with a Core ML encoder. We will \
                    capture microphone audio, normalize it to 16 kHz mono Float32, maintain \
                    a sliding analysis window, and trigger streaming transcription. \
                    The end result is a responsive transcript rendered in SwiftUI.
                    """
                )

                DividerLine()

                // MARK: What you will build

                Subtitle("What You Will Build")
                BodyText(
                    """
                    A reusable `SpeechToTextViewModel` that exposes `transcription` and \
                    `isRecording`, plus a simple `SpeechToTextView` that starts/stops capture. \
                    The ViewModel hides all the audio plumbing and runs Whisper asynchronously.
                    """
                )

                // MARK: Requirements

                Subtitle("Requirements")
                BodyText("Before running the demo, make sure to:")
                CodeBlock(
                    """
                    • Add both model files to the target (Target Membership):
                      - ggml-tiny.en.bin (or other ggml variant)
                      - ggml-tiny.en-encoder.mlmodelc
                    • Include in Info.plist:
                      - NSMicrophoneUsageDescription
                    • Test on a physical device (the Simulator has limited audio behavior).
                    • If you speak Portuguese, prefer a multilingual model (e.g., ggml-tiny.bin)
                      and optionally set language to \"pt\" during decoding (Whisper can auto-detect).
                    """
                )

                DividerLine()

                // MARK: 1) Model loading

                Subtitle("1) Model Loading (file: SpeechToTextViewModel.swift — init())")
                BodyText(
                    """
                    We load the ggml decoder (.bin) and ensure the Core ML encoder (.mlmodelc) \
                    is present. If the files are not found in the bundle, we inform the user \
                    via `transcription` (instead of crashing). The snippet below is the exact \
                    structure used in our ViewModel’s initializer.
                    """
                )
                CodeBlock(
                    #"""
                    // FILE: SpeechToTextViewModel.swift
                    // SECTION: Initialization (init())
                    
                    init() {
                        let binaryModelCandidates: [String] = [
                            "ggml-tiny.en",
                            "ggml-tiny",
                            "tiny.en",
                            "tiny"
                        ]
                        let encoderModelCandidates: [String] = [
                            "ggml-tiny.en-encoder",
                            "ggml-tiny-encoder"
                        ]
                        let directoryCandidates: [String] = [
                            "",
                            "models",
                            "Model",
                            "Sample/Model"
                        ]
                    
                        guard
                            let binaryModelURL: URL = Self.locateResource(
                                basenames: binaryModelCandidates,
                                ext: "bin",
                                subdirectories: directoryCandidates
                            ),
                            let _: URL = Self.locateResource(
                                basenames: encoderModelCandidates,
                                ext: "mlmodelc",
                                subdirectories: directoryCandidates
                            )
                        else {
                            DispatchQueue.main.async {
                                self.transcription =
                                "Whisper model files were not found in the app bundle."
                            }
                            return
                        }
                    
                        // Initialize the ggml Whisper handle using the .bin file.
                        whisper = Whisper(fromFileURL: binaryModelURL)
                    }
                    """#
                )

                // MARK: 2) Audio session

                Subtitle("2) Audio Session (file: SpeechToTextViewModel.swift — configureAudioSession())")
                BodyText(
                    """
                    This configuration enables voice processing, requests 16 kHz (preferred),
                    uses short IO buffers for lower latency, and selects one input channel.
                    If the system cannot honor a preference (e.g., exact sample rate),
                    the conversion path will resample to 16 kHz for Whisper.
                    """
                )
                CodeBlock(
                    #"""
                    // FILE: SpeechToTextViewModel.swift
                    // SECTION: Private — Audio session configuration
                    
                    @discardableResult
                    private func configureAudioSession() -> Bool {
                        let session: AVAudioSession = AVAudioSession.sharedInstance()
                    
                        do {
                            try session.setCategory(
                                .playAndRecord,
                                mode: .voiceChat,
                                options: [
                                    .duckOthers,
                                    .defaultToSpeaker,
                                    .allowBluetooth
                                ]
                            )
                        } catch {
                            // We proceed; conversion will still work if category fallback occurs.
                        }
                    
                        do {
                            try session.setPreferredSampleRate(
                                targetSampleRate  // 16_000 Hz
                            )
                        } catch {
                            // Not critical; we will resample in software if needed.
                        }
                    
                        do {
                            try session.setPreferredIOBufferDuration(
                                0.01  // ~10 ms
                            )
                        } catch {
                            // Fallback to system default IO buffer size.
                        }
                    
                        do {
                            try session.setActive(
                                true,
                                options: .notifyOthersOnDeactivation
                            )
                        } catch {
                            return false
                        }
                    
                        do {
                            try session.setPreferredInputNumberOfChannels(1)
                        } catch {
                            // If device remains stereo, we will downmix in software.
                        }
                    
                        return true
                    }
                    """#
                )

                // MARK: 3) Recording + normalization

                Subtitle("3) Recording + Normalization (file: SpeechToTextViewModel.swift — startRecording())")
                BodyText(
                    """
                    We install a tap on the input node. If the incoming format is already \
                    Float32 mono at 16 kHz, we append frames directly (fast path). Otherwise, \
                    we downmix to mono and resample to 16 kHz (convert path). We keep at most \
                    two window lengths of audio in memory and trigger inference opportunistically.
                    """
                )
                CodeBlock(
                    #"""
                    // FILE: SpeechToTextViewModel.swift
                    // SECTION: Public — startRecording()
                    
                    func startRecording() {
                        requestPermissions()
                    
                        guard configureAudioSession() else { return }
                    
                        let input: AVAudioInputNode = audioEngine.inputNode
                        inputNode = input
                    
                        let inputFormat: AVAudioFormat = input.outputFormat(forBus: 0)
                        let inputSampleRate: Double = inputFormat.sampleRate
                        let inputChannels: Int = Int(inputFormat.channelCount)
                    
                        let tapBufferSize: AVAudioFrameCount = 8_192
                        let windowFrameCount: Int = Int(windowSeconds * targetSampleRate)
                    
                        // Reset state for a fresh capture session.
                        accumulatedFrames.removeAll(keepingCapacity: true)
                        isRunningInference = false
                        lastInferenceTime = 0
                        hasTriggeredOnce = false
                    
                        // Fast path: already Float32 mono @ 16 kHz?
                        let isAlreadyTargetFormat: Bool =
                            abs(inputSampleRate - targetSampleRate) < 0.5 &&
                            inputChannels == 1 &&
                            inputFormat.commonFormat == .pcmFormatFloat32
                    
                        if isAlreadyTargetFormat {
                            input.installTap(
                                onBus: 0,
                                bufferSize: tapBufferSize,
                                format: inputFormat
                            ) { [weak self] inputBuffer, _ in
                                guard let strongSelf = self else { return }
                    
                                let frameCount: Int = Int(inputBuffer.frameLength)
                                guard frameCount > 0 else { return }
                                guard let ptr = inputBuffer.floatChannelData?[0] else { return }
                    
                                strongSelf.accumulatedFrames.append(
                                    contentsOf: UnsafeBufferPointer(
                                        start: ptr,
                                        count: frameCount
                                    )
                                )
                    
                                if strongSelf.accumulatedFrames.count > windowFrameCount * 2 {
                                    let toRemove: Int =
                                        strongSelf.accumulatedFrames.count - windowFrameCount * 2
                                    strongSelf.accumulatedFrames.removeFirst(toRemove)
                                }
                    
                                strongSelf.maybeTriggerInference(
                                    windowFrameCount: windowFrameCount,
                                    contextTag: "fast-path"
                                )
                            }
                        } else {
                            // Convert path: downmix -> resample -> append.
                            guard
                                let monoFormat: AVAudioFormat = AVAudioFormat(
                                    commonFormat: .pcmFormatFloat32,
                                    sampleRate: inputSampleRate,
                                    channels: 1,
                                    interleaved: false
                                ),
                                let whisperFormat: AVAudioFormat = AVAudioFormat(
                                    commonFormat: .pcmFormatFloat32,
                                    sampleRate: targetSampleRate,
                                    channels: 1,
                                    interleaved: false
                                ),
                                let downmix: AVAudioConverter = AVAudioConverter(
                                    from: inputFormat,
                                    to: monoFormat
                                ),
                                let resample: AVAudioConverter = AVAudioConverter(
                                    from: monoFormat,
                                    to: whisperFormat
                                )
                            else { return }
                    
                            let ratio: Double = targetSampleRate / inputSampleRate
                    
                            input.installTap(
                                onBus: 0,
                                bufferSize: tapBufferSize,
                                format: inputFormat
                            ) { [weak self] inputBuffer, _ in
                                guard let strongSelf = self else { return }
                    
                                let inFrames: Int = Int(inputBuffer.frameLength)
                                guard inFrames > 0 else { return }
                    
                                // Stage 1: downmix to mono at device sample rate.
                                guard
                                    let monoPCM: AVAudioPCMBuffer = AVAudioPCMBuffer(
                                        pcmFormat: monoFormat,
                                        frameCapacity: AVAudioFrameCount(inFrames)
                                    )
                                else { return }
                    
                                var downmixError: NSError?
                                var fedOnce: Bool = false
                                _ = downmix.convert(
                                    to: monoPCM,
                                    error: &downmixError
                                ) { _, outStatus in
                                    if fedOnce || inputBuffer.frameLength == 0 {
                                        outStatus.pointee = .noDataNow
                                        return nil
                                    }
                                    fedOnce = true
                                    outStatus.pointee = .haveData
                                    return inputBuffer
                                }
                                if downmixError != nil { return }
                    
                                let monoFrames: Int = Int(monoPCM.frameLength)
                                guard monoFrames > 0 else { return }
                    
                                // Stage 2: resample mono to 16 kHz Float32.
                                let estimatedOut: Int = Int(
                                    ceil(Double(monoFrames) * ratio)
                                )
                                let capacity: Int = max(monoFrames, estimatedOut)
                    
                                guard
                                    let outPCM: AVAudioPCMBuffer = AVAudioPCMBuffer(
                                        pcmFormat: whisperFormat,
                                        frameCapacity: AVAudioFrameCount(capacity)
                                    )
                                else { return }
                    
                                var resampleError: NSError?
                                var provided: Bool = false
                                _ = resample.convert(
                                    to: outPCM,
                                    error: &resampleError
                                ) { _, outStatus in
                                    if provided || monoPCM.frameLength == 0 {
                                        outStatus.pointee = .noDataNow
                                        return nil
                                    }
                                    provided = true
                                    outStatus.pointee = .haveData
                                    return monoPCM
                                }
                                if resampleError != nil { return }
                    
                                let produced: Int = Int(outPCM.frameLength)
                                guard produced > 0 else { return }
                                guard let ptr = outPCM.floatChannelData?[0] else { return }
                    
                                strongSelf.accumulatedFrames.append(
                                    contentsOf: UnsafeBufferPointer(
                                        start: ptr,
                                        count: produced
                                    )
                                )
                    
                                if strongSelf.accumulatedFrames.count > windowFrameCount * 2 {
                                    let toRemove: Int =
                                        strongSelf.accumulatedFrames.count - windowFrameCount * 2
                                    strongSelf.accumulatedFrames.removeFirst(toRemove)
                                }
                    
                                strongSelf.maybeTriggerInference(
                                    windowFrameCount: windowFrameCount,
                                    contextTag: "convert-path"
                                )
                            }
                        }
                    
                        do {
                            try audioEngine.start()
                            isRecording = true
                        } catch {
                            // If engine fails to start, recording does not begin.
                        }
                    }
                    """#
                )

                // MARK: 4) Triggering inference

                Subtitle("4) Triggering Inference (file: SpeechToTextViewModel.swift — maybeTriggerInference)")
                BodyText(
                    """
                    We trigger only when enough frames are available, the debounce interval \
                    has elapsed, and the audio level is above a minimal dBFS threshold. \
                    Decoding happens off the main actor; text updates are committed on the \
                    main actor to keep SwiftUI consistent.
                    """
                )
                CodeBlock(
                    #"""
                    // FILE: SpeechToTextViewModel.swift
                    // SECTION: Private — Inference trigger
                    
                    private func maybeTriggerInference(
                        windowFrameCount: Int,
                        contextTag: String
                    ) {
                        let now: TimeInterval = Date.timeIntervalSinceReferenceDate
                        let minFirstFrames: Int = Int(minFirstTriggerSeconds * targetSampleRate)
                    
                        let hasFullWindow: Bool = accumulatedFrames.count >= windowFrameCount
                        let hasEnoughForFirst: Bool =
                            accumulatedFrames.count >= minFirstFrames || hasTriggeredOnce
                        let isDebounced: Bool = (now - lastInferenceTime) >= hopSeconds
                        let canTrigger: Bool =
                            !isRunningInference && hasEnoughForFirst && isDebounced
                    
                        guard canTrigger else { return }
                    
                        // Slice a full window when possible, otherwise the minimal first window.
                        let desiredCount: Int = hasFullWindow
                            ? windowFrameCount
                            : max(accumulatedFrames.count, minFirstFrames)
                    
                        let startIndex: Int = max(0, accumulatedFrames.count - desiredCount)
                        let frames: [Float] = Array(
                            accumulatedFrames[startIndex..<accumulatedFrames.count]
                        )
                    
                        // Avoid decoding silence.
                        let (_, dbFS) = Self.audioLevelMetrics(for: frames)
                        guard dbFS >= minDecibelsFullScaleToTranscribe else { return }
                    
                        lastInferenceTime = now
                        isRunningInference = true
                    
                        let localWhisper: Whisper? = whisper
                        let framesCopy: [Float] = frames
                    
                        Task.detached { [weak self, framesCopy, localWhisper] in
                            guard let strongSelf = self else { return }
                            guard let whisperInstance = localWhisper else {
                                await MainActor.run { strongSelf.isRunningInference = false }
                                return
                            }
                    
                            do {
                                let segments: [Segment] = try await whisperInstance.transcribe(
                                    audioFrames: framesCopy
                                )
                                let text: String = segments
                                    .map(\.text)
                                    .joined(separator: " ")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                                await MainActor.run {
                                    if !text.isEmpty {
                                        strongSelf.transcription += strongSelf.transcription.isEmpty
                                            ? text
                                            : " \(text)"
                                        strongSelf.hasTriggeredOnce = true
                                    }
                                    strongSelf.isRunningInference = false
                                }
                            } catch {
                                await MainActor.run {
                                    strongSelf.isRunningInference = false
                                }
                            }
                        }
                    }
                    """#
                )

                // MARK: 5) Minimal UI

                Subtitle("5) Minimal UI (file: SpeechToTextView.swift — body)")
                BodyText(
                    """
                    The demo view renders the live transcript and exposes a single \
                    button to start/stop recording. Accessibility labels are set \
                    to support VoiceOver. The text area is scrollable and wraps long lines.
                    """
                )
                CodeBlock(
                    #"""
                    // FILE: SpeechToTextView.swift
                    // SECTION: body
                    
                    struct SpeechToTextView: View {
                        @StateObject private var viewModel = SpeechToTextViewModel()
                    
                        var body: some View {
                            VStack(alignment: .leading, spacing: 16) {
                                Title("Speech-to-Text with Core ML")
                                BodyText(
                                    "This example uses Whisper via Core ML to transcribe your speech in real time."
                                )
                    
                                DividerLine()
                    
                                Subtitle("Live Transcription")
                                ScrollView {
                                    Text(viewModel.transcription)
                                        .font(.system(size: 16))
                                        .padding()
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                        .background(Color.backgroundSurface)
                                        .cornerRadius(10)
                                }
                    
                                Button(action: {
                                    viewModel.toggleRecording()
                                }) {
                                    Text(
                                        viewModel.isRecording
                                        ? "Stop Recording"
                                        : "Start Recording"
                                    )
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .accessibilityLabel(
                                    viewModel.isRecording
                                    ? "Stop Recording"
                                    : "Start Recording"
                                )
                            }
                            .padding(20)
                            .onAppear { viewModel.requestPermissions() }
                        }
                    }
                    """#
                )

                DividerLine()

                // MARK: Tuning

                Subtitle("Tuning and Troubleshooting")
                BodyText(
                    """
                    • If recognition is too sensitive or not sensitive enough, adjust:
                      `minDecibelsFullScaleToTranscribe` (e.g., from −45 dBFS to −55 dBFS).
                    • Increase `windowSeconds` for more context (slower, more accurate),
                      or decrease for lower latency.
                    • Increase `hopSeconds` to trigger less frequently if your device \
                      is resource-constrained.
                    • Make sure the model files are included in your target and not marked \
                      as “Remove on Install”.
                    • Run on a device; the Simulator does not reflect actual microphone \
                      and audio route behavior.
                    """
                )

                DividerLine()

                // MARK: Live Demo link

                Subtitle("Live Demo")
                NavigationLink(destination: SpeechToTextView()) {
                    Text("Open Speech-to-Text Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
