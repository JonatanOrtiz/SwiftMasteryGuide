//
//  CoreHapticsGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct CoreHapticsGuideView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SomeVideoViewController {
        return SomeVideoViewController()
    }

    func updateUIViewController(_ uiViewController: SomeVideoViewController, context: Context) {
        // updateUIViewController
    }
}

import CoreHaptics
import UIKit
import AVFoundation
import Accelerate

class SomeVideoViewController: UIViewController {
    private let videoView = VideoView()
    private var audioAnalyzer: AudioHapticAnalyzer?
    private var audioDownloadTask: URLSessionDownloadTask?
    private var videoDuration: Double = 0.0
    private var timeObserver: Any?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let audioURL = URL(string: "https://sfpf-bills-hom.ppay.me/vehicle-hub-bff/campaigns/sauber/sauber_promo_audio_home.m4a")!
        audioDownloadTask = downloadAudioFile(from: audioURL) { [weak self] localURL in
            guard let self = self, let localURL = localURL else { return }
            let analyzer = AudioHapticAnalyzer()
            self.audioAnalyzer = analyzer
            analyzer.playAndAnalyzeAudio(url: localURL)
            self.videoView.play { [weak self] duration in
                self?.videoDuration = duration
                self?.setupVideoTimeObserver()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        videoView.pause()
        audioAnalyzer?.stop()
        audioAnalyzer = nil
        audioDownloadTask?.cancel()
        audioDownloadTask = nil
        if let observer = timeObserver {
            videoView.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func setupVideoTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = videoView.addPeriodicTimeObserver(forInterval: interval) { [weak self] time in
            guard let self = self else { return }
            let currentTime = CMTimeGetSeconds(time)
            let isInLastThreeSeconds = currentTime >= (self.videoDuration - 3.0)
            self.audioAnalyzer?.setVideoInLastSecond(isInLastThreeSeconds)
        }
    }

    @discardableResult
    private func downloadAudioFile(from url: URL, completion: @escaping (URL?) -> Void) -> URLSessionDownloadTask {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: localURL)
            do {
                try FileManager.default.copyItem(at: tempURL, to: localURL)
                DispatchQueue.main.async { completion(localURL) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        task.resume()
        return task
    }
}

// AVAudioEngine Analyzer
final class AudioHapticAnalyzer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var lastHapticTime = Date()
    private var isVideoInLastSecond = false
    private var hapticEngine: CHHapticEngine?
    private var supportsCoreHaptics: Bool = {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }()

    init() {
        if supportsCoreHaptics {
            do {
                hapticEngine = try CHHapticEngine()
                try hapticEngine?.start()
            } catch {
                print("Error instantiating CHHapticEngine: \(error)")
            }
        }
    }

    func playAndAnalyzeAudio(url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            print("Error opening audio file: \(error)")
            return
        }
        let format = audioFile!.processingFormat

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let rms = self.calculateRMS(buffer: buffer)
            let sampleRate = Float(format.sampleRate)
            let freq = self.dominantFrequency(buffer: buffer, sampleRate: sampleRate)

            if self.isVideoInLastSecond {
                return
            }

            let freqIntensity = self.calculateFrequencyIntensity(freq: freq, rms: rms)

            if freqIntensity > 0.4 && Date().timeIntervalSince(self.lastHapticTime) > 0.1 {
                self.lastHapticTime = Date()
                self.performFrequencyHaptic(freq: freq, intensity: freqIntensity)
            }
        }

        do {
            try engine.start()
            if let audioFile = audioFile {
                playerNode.scheduleFile(audioFile, at: nil)
                playerNode.play()
            }
        } catch {
            print("Error instantiating engine: \(error)")
        }
    }

    private func calculateFrequencyIntensity(freq: Float, rms: Float) -> Float {
        if freq <= 25 || freq >= 15000 {
            return 0.0
        }

        let f = freq

        if f >= 30 && f <= 199 {
            let t = (f - 30) / 169
            return 0.2 + 0.6 * (1 - t * t)
        } else if f >= 200 && f <= 300 {
            let t = (f - 200) / 100
            return 0.1 + 0.2 * (1 - t)
        } else if f >= 600 && f <= 6000 {
            let t = (f - 600) / 5400
            let baseIntensity = 1.0 - 0.8 * t
            let wave1 = sin(t * Float.pi * 3) * 0.15
            let wave2 = cos(t * Float.pi * 5) * 0.10
            let wave3 = sin(t * Float.pi * 1.2) * 0.08
            let variation = wave1 + wave2 + wave3
            let finalIntensity = baseIntensity + variation
            return max(0.15, min(1.0, finalIntensity))
        } else if f >= 301 && f <= 599 {
            let t = (f - 301) / (599 - 301)
            let wave1 = sin(t * Float.pi * 1.5)
            let wave2 = cos(t * Float.pi * 2.5) * 0.4
            let wave3 = sin(t * Float.pi * 4) * 0.2
            let combinedWave = wave1 + wave2 + wave3
            let baseIntensity = 0.05 + 0.20 * ((combinedWave + 1.0) / 2.0)
            let voiceRegion: Float = abs(t - 0.4) < 0.25 ? 0.8 : 1.0
            return baseIntensity * voiceRegion
        } else {
            return 0.0
        }
    }

    private func performFrequencyHaptic(freq: Float, intensity: Float) {
        guard supportsCoreHaptics, let engine = hapticEngine else {
            DispatchQueue.main.async {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
            return
        }

        let sharpness: Float = freq < 100 ? 0.5 : (freq >= 600 ? 1.0 : 0.6)
        let duration: Double = freq < 100 ? 0.4 : (freq >= 600 ? 1.5 : 0.5)

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: duration
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Error playing haptic: \(error)")
        }
    }

    func dominantFrequency(buffer: AVAudioPCMBuffer, sampleRate: Float) -> Float {
        guard let channelData = buffer.floatChannelData?.pointee else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let log2n = vDSP_Length(log2(Float(frameCount)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else { return 0 }

        var windowedBuffer = [Float](repeating: 0, count: frameCount)
        vDSP_hann_window(&windowedBuffer, vDSP_Length(frameCount), Int32(vDSP_HANN_NORM))
        var windowedSignal = [Float](repeating: 0, count: frameCount)
        vDSP_vmul(channelData, 1, windowedBuffer, 1, &windowedSignal, 1, vDSP_Length(frameCount))

        var realp = [Float](repeating: 0, count: frameCount/2)
        var imagp = [Float](repeating: 0, count: frameCount/2)

        let frequency: Float = realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowedSignal.withUnsafeBufferPointer { signalPtr in
                    signalPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frameCount) { typeConvertedTransferBuffer in
                        vDSP_ctoz(typeConvertedTransferBuffer, 2, &splitComplex, 1, vDSP_Length(frameCount/2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, Int32(FFT_FORWARD))
                var magnitudes = [Float](repeating: 0, count: frameCount/2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(frameCount/2))

                var maxMag: Float = 0
                var maxIndex: vDSP_Length = 0
                vDSP_maxvi(&magnitudes, 1, &maxMag, &maxIndex, vDSP_Length(frameCount/2))
                vDSP_destroy_fftsetup(fftSetup)

                let dominantFreq = Float(maxIndex) * sampleRate / Float(frameCount)

                return dominantFreq
            }
        }

        return frequency
    }

    func setVideoInLastSecond(_ inLastSecond: Bool) {
        isVideoInLastSecond = inLastSecond
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelDataValue[i] * channelDataValue[i]
        }
        return sqrt(sum / Float(frameLength))
    }
}

final class VideoView: UIView {
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupPlayerLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setupPlayerLayer()
    }

    private func setupPlayerLayer() {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        playerLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func play(completion: ((Double) -> Void)? = nil) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error configuring AVAudioSession: \(error)")
        }
        let urlString = "https://sfpf-bills-hom.ppay.me/vehicle-hub-bff/campaigns/sauber/sauber_promo_video_home.mp4"
        guard let url = URL(string: urlString) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true

        if let completion = completion {
            item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
            self.durationCallback = completion
        }

        player.play()
    }

    private var durationCallback: ((Double) -> Void)?

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let item = object as? AVPlayerItem, item.status == .readyToPlay {
            let duration = CMTimeGetSeconds(item.duration)
            durationCallback?(duration)
            durationCallback = nil
            item.removeObserver(self, forKeyPath: "status")
        }
    }

    func addPeriodicTimeObserver(forInterval interval: CMTime, using block: @escaping (CMTime) -> Void) -> Any {
        return player.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: block)
    }

    func removeTimeObserver(_ observer: Any) {
        player.removeTimeObserver(observer)
    }

    func pause() {
        player.pause()
    }
}
