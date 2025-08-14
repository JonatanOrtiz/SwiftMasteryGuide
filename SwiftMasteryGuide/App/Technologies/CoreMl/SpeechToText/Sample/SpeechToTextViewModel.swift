//
//  SpeechToTextViewModel.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 13/08/25.
//

import SwiftUI
import SwiftWhisper
import AVFoundation

/// A view model that:
/// - Captures microphone audio via `AVAudioEngine`.
/// - Ensures 16 kHz, mono, Float32 PCM frames (downmix + resample when needed).
/// - Accumulates frames into a sliding window and triggers streaming transcription.
/// - Uses ggml Whisper model with Core ML encoder (if `.mlmodelc` is present).
/// - Publishes transcribed text for SwiftUI.
///
/// The logic is structured to avoid force unwraps, work on device safely,
/// and keep UI updates on the main actor.
///
/// ### Pipeline
/// 1. Configure `AVAudioSession` for voice processing (`.playAndRecord`, `.voiceChat`).
/// 2. Install an audio tap on the input node.
/// 3. Convert buffers to the Whisper-required format (16 kHz, mono, Float32).
/// 4. Accumulate samples in a ring-like buffer with a fixed analysis window.
/// 5. Trigger inference when enough samples are available and the debounce interval has passed.
/// 6. Append non-empty transcription to `transcription`.
final class SpeechToTextViewModel: ObservableObject {

    // MARK: - Published state

    /// The concatenated transcription text shown in the UI.
    @Published var transcription: String = ""

    /// Whether audio capture is currently running.
    @Published var isRecording: Bool = false

    // MARK: - Whisper model

    /// Whisper model handle (decoder in ggml; encoder may run on Core ML).
    private var whisper: Whisper?

    // MARK: - Audio capture

    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?

    // MARK: - Windowing and triggering

    /// Whisper expects 16 kHz audio.
    private let targetSampleRate: Double = 16_000

    /// Analysis window size in seconds for each inference.
    private let windowSeconds: Double = 3.0

    /// Minimum interval in seconds between consecutive inferences (hop size).
    private let hopSeconds: Double = 1.0

    /// Minimum seconds of audio required before allowing the first inference.
    private let minFirstTriggerSeconds: Double = 2.0

    /// Level gate: minimum decibels full scale required for inference.
    /// Lower (e.g., -65 dBFS) is more permissive for quiet inputs.
    private let minDecibelsFullScaleToTranscribe: Double = -45.0

    /// Accumulated audio frames (Float32, mono, 16 kHz).
    private var accumulatedFrames: [Float] = []

    /// Prevents overlapping inferences.
    private var isRunningInference: Bool = false

    /// Debounce control for the sliding window.
    private var lastInferenceTime: TimeInterval = 0

    /// Indicates that at least one inference has already been performed.
    private var hasTriggeredOnce: Bool = false

    // MARK: - Initialization

    /// Initializes the view model and loads Whisper model files from the app bundle.
    ///
    /// The loader searches for:
    /// - A ggml decoder binary (`.bin`) – e.g., `ggml-tiny.bin` or `ggml-tiny.en.bin`.
    /// - A Core ML encoder bundle (`.mlmodelc`) – e.g., `ggml-tiny-encoder.mlmodelc`.
    ///
    /// If the model cannot be found, `transcription` is set with a minimal diagnostic message.
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
                self.transcription = "Whisper model files were not found in the app bundle."
            }
            return
        }

        whisper = Whisper(fromFileURL: binaryModelURL)
    }

    // MARK: - Public controls

    /// Requests microphone permission using the appropriate iOS API.
    func requestPermissions() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }

    /// Toggles audio capture on or off.
    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    // MARK: - Audio session configuration

    /// Configures `AVAudioSession` for voice capture with voice processing enabled.
    ///
    /// - Returns: `true` if activation succeeded; `false` otherwise.
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
            // Keep going; conversion path still works even if category fallback occurs.
        }

        do {
            try session.setPreferredSampleRate(
                targetSampleRate
            )
        } catch {
            // If not honored, software resampling will occur.
        }

        do {
            try session.setPreferredIOBufferDuration(
                0.01
            )
        } catch {
            // Fall back to system default buffer duration.
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
            // If the device keeps stereo input, software downmix will occur.
        }

        return true
    }

    // MARK: - Recording + conversion + windowing

    /// Starts audio capture, installs the input tap, and begins accumulating frames.
    ///
    /// The tap either:
    /// - Fast path: directly appends Float32 mono 16 kHz frames, or
    /// - Convert path: downmixes to mono and resamples to 16 kHz Float32.
    func startRecording() {
        requestPermissions()

        guard configureAudioSession() else {
            return
        }

        let input: AVAudioInputNode = audioEngine.inputNode
        inputNode = input

        let inputFormat: AVAudioFormat = input.outputFormat(forBus: 0)
        let inputSampleRate: Double = inputFormat.sampleRate
        let inputChannels: Int = Int(inputFormat.channelCount)

        let tapBufferSize: AVAudioFrameCount = 8_192
        let windowFrameCount: Int = Int(windowSeconds * targetSampleRate)

        // Reset state
        accumulatedFrames.removeAll(keepingCapacity: true)
        isRunningInference = false
        lastInferenceTime = 0
        hasTriggeredOnce = false

        // Determine whether the input is already in Whisper’s required format.
        let isAlreadyTargetFormat: Bool =
        abs(inputSampleRate - targetSampleRate) < 0.5 &&
        inputChannels == 1 &&
        inputFormat.commonFormat == .pcmFormatFloat32

        if isAlreadyTargetFormat {
            // Fast path: directly append Float32 frames.
            input.installTap(
                onBus: 0,
                bufferSize: tapBufferSize,
                format: inputFormat
            ) { [weak self] inputBuffer, _ in
                guard let strongSelf = self else { return }

                let frameCount: Int = Int(inputBuffer.frameLength)
                guard frameCount > 0 else { return }
                guard let floatChannelPointer = inputBuffer.floatChannelData?[0] else { return }

                strongSelf.accumulatedFrames.append(
                    contentsOf: UnsafeBufferPointer(
                        start: floatChannelPointer,
                        count: frameCount
                    )
                )

                // Keep up to 2× window frames to limit memory growth.
                if strongSelf.accumulatedFrames.count > windowFrameCount * 2 {
                    let toRemove: Int = strongSelf.accumulatedFrames.count - windowFrameCount * 2
                    strongSelf.accumulatedFrames.removeFirst(toRemove)
                }

                strongSelf.maybeTriggerInference(
                    windowFrameCount: windowFrameCount,
                    contextTag: "fast-path"
                )
            }
        } else {
            // Convert path: downmix to mono (device SR) then resample to 16 kHz Float32.
            guard
                let downmixMonoFormat: AVAudioFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: inputSampleRate,
                    channels: 1,
                    interleaved: false
                ),
                let whisperOutputFormat: AVAudioFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: targetSampleRate,
                    channels: 1,
                    interleaved: false
                ),
                let downmixConverter: AVAudioConverter = AVAudioConverter(
                    from: inputFormat,
                    to: downmixMonoFormat
                ),
                let resampleConverter: AVAudioConverter = AVAudioConverter(
                    from: downmixMonoFormat,
                    to: whisperOutputFormat
                )
            else {
                return
            }

            let sampleRateRatio: Double = targetSampleRate / inputSampleRate

            input.installTap(
                onBus: 0,
                bufferSize: tapBufferSize,
                format: inputFormat
            ) { [weak self] inputBuffer, _ in
                guard let strongSelf = self else { return }

                let inputFrameCount: Int = Int(inputBuffer.frameLength)
                guard inputFrameCount > 0 else { return }

                // Stage 1: downmix to mono at device sample rate
                guard
                    let intermediateMonoBuffer: AVAudioPCMBuffer = AVAudioPCMBuffer(
                        pcmFormat: downmixMonoFormat,
                        frameCapacity: AVAudioFrameCount(inputFrameCount)
                    )
                else {
                    return
                }

                var downmixError: NSError?
                var suppliedInputOnce: Bool = false
                _ = downmixConverter.convert(
                    to: intermediateMonoBuffer,
                    error: &downmixError
                ) { _, outStatus in
                    if suppliedInputOnce || inputBuffer.frameLength == 0 {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedInputOnce = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                if downmixError != nil { return }

                let intermediateFrames: Int = Int(intermediateMonoBuffer.frameLength)
                guard intermediateFrames > 0 else { return }

                // Stage 2: resample mono to 16 kHz Float32
                let estimatedOutputFrames: Int = Int(
                    ceil(Double(intermediateFrames) * sampleRateRatio)
                )
                let capacityFrames: Int = max(intermediateFrames, estimatedOutputFrames)

                guard
                    let whisperInputBuffer: AVAudioPCMBuffer = AVAudioPCMBuffer(
                        pcmFormat: whisperOutputFormat,
                        frameCapacity: AVAudioFrameCount(capacityFrames)
                    )
                else {
                    return
                }

                var resampleError: NSError?
                var suppliedMonoOnce: Bool = false
                _ = resampleConverter.convert(
                    to: whisperInputBuffer,
                    error: &resampleError
                ) { _, outStatus in
                    if suppliedMonoOnce || intermediateMonoBuffer.frameLength == 0 {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedMonoOnce = true
                    outStatus.pointee = .haveData
                    return intermediateMonoBuffer
                }
                if resampleError != nil { return }

                let producedFrameCount: Int = Int(whisperInputBuffer.frameLength)
                guard producedFrameCount > 0 else { return }
                guard let floatChannelPointer = whisperInputBuffer.floatChannelData?[0] else { return }

                strongSelf.accumulatedFrames.append(
                    contentsOf: UnsafeBufferPointer(
                        start: floatChannelPointer,
                        count: producedFrameCount
                    )
                )

                // Keep up to 2× window frames to limit memory growth.
                if strongSelf.accumulatedFrames.count > windowFrameCount * 2 {
                    let toRemove: Int = strongSelf.accumulatedFrames.count - windowFrameCount * 2
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
            // If the engine fails to start, recording does not begin.
        }
    }

    /// Stops audio capture, removes the input tap, and clears buffers.
    func stopRecording() {
        audioEngine.stop()
        inputNode?.removeTap(onBus: 0)
        isRecording = false
        accumulatedFrames.removeAll(keepingCapacity: false)
        isRunningInference = false
        hasTriggeredOnce = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Inference trigger

    /// Evaluates whether an inference should be triggered based on window size,
    /// debounce interval, and audio level threshold. If conditions are satisfied,
    /// this method performs an asynchronous transcription using Whisper and appends
    /// any non-empty text to `transcription`.
    ///
    /// - Parameters:
    ///   - windowFrameCount: Number of frames in the analysis window.
    ///   - contextTag: A contextual string to help identify the code path
    ///                 (e.g., `"fast-path"` or `"convert-path"`). Not logged.
    private func maybeTriggerInference(
        windowFrameCount: Int,
        contextTag: String
    ) {
        let currentTime: TimeInterval = Date.timeIntervalSinceReferenceDate
        let minFramesForFirst: Int = Int(minFirstTriggerSeconds * targetSampleRate)
        let hasFullWindow: Bool = accumulatedFrames.count >= windowFrameCount
        let hasEnoughForFirst: Bool = accumulatedFrames.count >= minFramesForFirst || hasTriggeredOnce
        let isDebouncedNow: Bool = (currentTime - lastInferenceTime) >= hopSeconds
        let canTrigger: Bool = (!isRunningInference && hasEnoughForFirst && isDebouncedNow)

        guard canTrigger else { return }

        // Slice either a full window or the minimal first window.
        let desiredCount: Int = hasFullWindow
        ? windowFrameCount
        : max(accumulatedFrames.count, minFramesForFirst)

        let startIndex: Int = max(0, accumulatedFrames.count - desiredCount)
        let framesForInference: [Float] = Array(accumulatedFrames[startIndex..<accumulatedFrames.count])

        // Gate by measured audio level to avoid wasting compute on silence.
        let (_, decibelsFullScale) = Self.audioLevelMetrics(
            for: framesForInference
        )
        guard decibelsFullScale >= minDecibelsFullScaleToTranscribe else { return }

        lastInferenceTime = currentTime
        isRunningInference = true

        let localWhisper: Whisper? = whisper
        let framesCopy: [Float] = framesForInference

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

    // MARK: - Utilities

    /// Computes simple audio level metrics.
    ///
    /// - Note: This uses a partial sampling to keep cost low for large buffers.
    /// - Parameter frames: Float32 PCM mono samples in the range `[-1, 1]`.
    /// - Returns: A tuple `(rootMeanSquare, decibelsFullScale)`. The dBFS reference is full scale = 1.0.
    private static func audioLevelMetrics(
        for frames: [Float]
    ) -> (Double, Double) {
        guard !frames.isEmpty else { return (0.0, -120.0) }

        var sumSquares: Double = 0
        let step: Int = max(1, frames.count / 8_000)
        var count: Int = 0
        var index: Int = 0

        while index < frames.count {
            let sample: Double = Double(frames[index])
            sumSquares += sample * sample
            count += 1
            index += step
        }

        guard count > 0 else { return (0.0, -120.0) }

        let rootMeanSquare: Double = sqrt(sumSquares / Double(count))
        let decibelsFullScale: Double = 20.0 * log10(max(rootMeanSquare, 1e-8))
        return (rootMeanSquare, decibelsFullScale)
    }

    /// Locates a resource in the main bundle by trying multiple base names and subdirectories.
    ///
    /// - Parameters:
    ///   - basenames: Candidate file base names without extension.
    ///   - ext: File extension (e.g., `"bin"` or `"mlmodelc"`).
    ///   - subdirectories: Candidate subdirectory names inside the bundle’s resource URL.
    /// - Returns: The first matching `URL` if found, otherwise `nil`.
    private static func locateResource(
        basenames: [String],
        ext: String,
        subdirectories: [String]
    ) -> URL? {
        let bundle: Bundle = .main

        for base in basenames {
            for directory in subdirectories {
                if directory.isEmpty,
                   let url: URL = bundle.url(
                    forResource: base,
                    withExtension: ext
                   ) {
                    return url
                }
                if let url: URL = bundle.url(
                    forResource: base,
                    withExtension: ext,
                    subdirectory: directory
                ) {
                    return url
                }
            }
        }

        if let root: URL = bundle.resourceURL {
            for base in basenames {
                for directory in subdirectories {
                    let candidate: URL = directory.isEmpty
                    ? root.appendingPathComponent("\(base).\(ext)")
                    : root
                        .appendingPathComponent(directory)
                        .appendingPathComponent("\(base).\(ext)")
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }
}
