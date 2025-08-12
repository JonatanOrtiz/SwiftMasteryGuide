//
//  CoreHapticsGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

/// A SwiftUI screen that explains (step-by-step) how to build
/// the SwiftUI + AVPlayer + MTAudioProcessingTap + Core Haptics demo.
/// Content is in English to match your Medium tutorial.
struct CoreHapticsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                Title("Audio‑Reactive Haptics in SwiftUI (iOS 15+)")

                Subtitle("What you’ll build")
                BodyText("""
                A SwiftUI video player that analyzes the video’s audio track in real time using MTAudioProcessingTap and triggers Core Haptics patterns based on RMS intensity and dominant frequency.
                """)

                Subtitle("Requirements")
                BulletList([
                    "iOS 15+ (async/await + AVAsset async loading).",
                    "Test on a real device (Core Haptics is not available in Simulator).",
                    "Frameworks: SwiftUI, AVKit, CoreHaptics, Accelerate."
                ])

                DividerLine()

                Subtitle("1) SwiftUI View")
                BodyText("Use a simple container view that renders the AVPlayer via VideoPlayer and delegates logic to a ViewModel:")
                CodeBlock("""
                struct CoreHapticsView: View {
                    @StateObject private var vm = CoreHapticsViewModel()
                
                    var body: some View {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            if let player = vm.player {
                                VideoPlayer(player: player).ignoresSafeArea()
                            }
                        }
                        .onAppear { vm.start() }
                        .onDisappear { vm.stop() }
                    }
                }
                """)

                Subtitle("2) ViewModel")
                BodyText("""
                The ViewModel prepares AVAudioSession, creates an AVPlayerItem, attaches the Audio Tap (via audioMix), and starts playback. Buffers from the tap feed DSP (RMS + FFT) to decide Core Haptics parameters.
                """)
                CodeBlock("""
                final class CoreHapticsViewModel: ObservableObject {
                    @Published var player: AVPlayer?
                    private var tap: AudioTap?
                    private let url = URL(string: "https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4")!
                    private let haptics = HapticsManager()
                    private var lastHapticTime = Date()
                
                    func start() {
                        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try? AVAudioSession.sharedInstance().setActive(true)
                
                        let item = AVPlayerItem(url: url)
                        let tap = AudioTap()
                        tap.onBuffer = { [weak self] blist, frames, sampleRate in
                            guard let self else { return }
                            let rms = Self.rms(from: blist, frames: frames)
                            let freq = Self.dominantFrequency(from: blist, frames: frames, sampleRate: sampleRate)
                            if rms > 0.2, Date().timeIntervalSince(self.lastHapticTime) > 0.1 {
                                self.lastHapticTime = Date()
                                let intensity = min(max((rms - 0.2) * 2, 0), 1)
                                let sharpness: Float = freq < 60 ? 0.1 : (freq < 120 ? 0.3 : 1.0)
                                self.haptics.play(intensity: intensity, sharpness: sharpness, duration: 0.5)
                            }
                        }
                
                        Task {
                            let mix = await tap.makeAudioMix(for: item)
                            await MainActor.run {
                                item.audioMix = mix
                                let p = AVPlayer(playerItem: item)
                                p.isMuted = false
                                self.player = p
                                self.tap = tap
                                p.play()
                            }
                        }
                    }
                
                    func stop() {
                        player?.pause()
                        player = nil
                        tap = nil
                    }
                
                    // RMS using Accelerate (vDSP)
                    private static func rms(from blist: UnsafePointer<AudioBufferList>, frames: CMItemCount) -> Float {
                        let abl = blist.pointee
                        guard abl.mNumberBuffers > 0, let mData = abl.mBuffers.mData else { return 0 }
                        let count = Int(frames)
                        let ptr = mData.bindMemory(to: Float.self, capacity: count)
                        var sum: Float = 0
                        vDSP_svesq(ptr, 1, &sum, vDSP_Length(count))
                        return sqrt(sum / Float(count))
                    }
                
                    // FFT to estimate dominant frequency
                    private static func dominantFrequency(from blist: UnsafePointer<AudioBufferList>,
                                                          frames: CMItemCount,
                                                          sampleRate: Float64) -> Float {
                        let n = Int(frames)
                        guard n > 1 else { return 0 }
                        let abl = blist.pointee
                        guard abl.mNumberBuffers > 0, let mData = abl.mBuffers.mData else { return 0 }
                        let inPtr = mData.bindMemory(to: Float.self, capacity: n)
                
                        var window = [Float](repeating: 0, count: n)
                        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
                
                        var signal = [Float](repeating: 0, count: n)
                        vDSP_vmul(inPtr, 1, window, 1, &signal, 1, vDSP_Length(n))
                
                        let log2n = vDSP_Length(log2(Float(n)))
                        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
                
                        var real = [Float](repeating: 0, count: n/2)
                        var imag = [Float](repeating: 0, count: n/2)
                        var freqOut: Float = 0
                
                        real.withUnsafeMutableBufferPointer { rPtr in
                            imag.withUnsafeMutableBufferPointer { iPtr in
                                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                                signal.withUnsafeBufferPointer { sPtr in
                                    sPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n) { cpx in
                                        vDSP_ctoz(cpx, 2, &split, 1, vDSP_Length(n/2))
                                    }
                                }
                                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                                var mags = [Float](repeating: 0, count: n/2)
                                mags.withUnsafeMutableBufferPointer { mPtr in
                                    vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(n/2))
                                }
                                var maxMag: Float = 0
                                var maxIdx: vDSP_Length = 0
                                vDSP_maxvi(&mags, 1, &maxMag, &maxIdx, vDSP_Length(n/2))
                                freqOut = Float(maxIdx) * Float(sampleRate) / Float(n)
                            }
                        }
                        vDSP_destroy_fftsetup(setup)
                        return freqOut
                    }
                }
                """)

                Subtitle("3) Haptics Manager")
                BodyText("A tiny wrapper around CHHapticEngine to play continuous events with intensity and sharpness derived from the audio:")
                CodeBlock("""
                final class HapticsManager {
                    private let engine: CHHapticEngine?
                    private let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics
                    init() {
                        if supports {
                            engine = try? CHHapticEngine()
                            try? engine?.start()
                        } else {
                            engine = nil
                        }
                    }
                    func play(intensity: Float, sharpness: Float, duration: TimeInterval) {
                        guard supports, let engine else {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            return
                        }
                        let event = CHHapticEvent(eventType: .hapticContinuous,
                                                  parameters: [
                                                    .init(parameterID: .hapticIntensity, value: intensity),
                                                    .init(parameterID: .hapticSharpness, value: sharpness)
                                                  ],
                                                  relativeTime: 0,
                                                  duration: duration)
                        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
                           let player = try? engine.makePlayer(with: pattern) {
                            try? player.start(atTime: 0)
                        }
                    }
                }
                """)

                Subtitle("4) Audio Tap")
                BodyText("""
                MTAudioProcessingTap intercepts the audio buffers of the AVPlayerItem. We attach it via an AVAudioMix input parameter.
                """)
                CodeBlock("""
                final class AudioTap {
                    var onBuffer: ((UnsafePointer<AudioBufferList>, CMItemCount, Float64) -> Void)?
                    private var tap: MTAudioProcessingTap!
                
                    init() {
                        var callbacks = MTAudioProcessingTapCallbacks(
                            version: kMTAudioProcessingTapCallbacksVersion_0,
                            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                            init: { tap, clientInfo, tapStorageOut in
                                tapStorageOut.pointee = clientInfo
                            },
                            finalize: { _ in },
                            prepare: { _, _, _ in },
                            unprepare: { _ in },
                            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                                var timeRange = CMTimeRange.invalid
                                let status = MTAudioProcessingTapGetSourceAudio(
                                    tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut
                                )
                                guard status == noErr else { return }
                                let storage = MTAudioProcessingTapGetStorage(tap)
                                let me = Unmanaged<AudioTap>.fromOpaque(storage).takeUnretainedValue()
                                let sampleRate = me.currentSampleRate(from: bufferListInOut) ?? 44100
                                me.onBuffer?(bufferListInOut, numberFramesOut.pointee, sampleRate)
                            }
                        )
                        var out: Unmanaged<MTAudioProcessingTap>?
                        MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &out)
                        tap = out!.takeRetainedValue()
                    }
                
                    func makeAudioMix(for item: AVPlayerItem) async -> AVAudioMix {
                        let tracks = (try? await item.asset.loadTracks(withMediaType: .audio)) ?? []
                        guard let track = tracks.first else { return AVAudioMix() }
                        let params = AVMutableAudioMixInputParameters(track: track)
                        params.audioTapProcessor = tap
                        let mix = AVMutableAudioMix()
                        mix.inputParameters = [params]
                        return mix
                    }
                
                    private func currentSampleRate(from bufferList: UnsafePointer<AudioBufferList>) -> Float64? {
                        let abl = bufferList.pointee
                        guard abl.mNumberBuffers > 0 else { return nil }
                        // If you need exact SR, derive from the audio format; many assets will be 44100 or 48000.
                        return 44100
                    }
                }
                """)
                
                DividerLine()

                Subtitle("Notes & Tips")
                BulletList([
                    "Always test on a real device—Core Haptics doesn’t run on the simulator.",
                    "Tune RMS threshold and haptic duration for your content.",
                    "If you target iOS 13/14, replace async track loading with the synchronous API and remove `Task`/`await`."
                ])

                DividerLine()

                Subtitle("Live Demo")
                NavigationLink(destination: CoreHapticsView()) {
                    Text("Open Core Haptics Demo")
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
