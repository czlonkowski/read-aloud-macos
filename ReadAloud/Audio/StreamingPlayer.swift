import Foundation
import AVFoundation

/// Wraps AVAudioEngine + AVAudioPlayerNode for gapless PCM streaming.
/// All public surface is `@MainActor` because we mutate AVAudioEngine state.
@MainActor
final class StreamingPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var currentFormat: AVAudioFormat?

    init() {
        engine.attach(player)
    }

    /// Enqueue Float32 mono samples at the given sample rate. Lazily (re)connects
    /// the player when the sample rate changes (e.g. between Kokoro 24kHz and
    /// Chatterbox 22.05kHz).
    func enqueue(_ samples: [Float], sampleRate: Double) {
        let format = ensureFormat(sampleRate: sampleRate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Stop and discard pending buffers.
    func flush() {
        player.stop()
        player.reset()
    }

    func pause() {
        if player.isPlaying { player.pause() }
    }

    func resume() {
        if !player.isPlaying { player.play() }
    }

    private func ensureFormat(sampleRate: Double) -> AVAudioFormat {
        if let current = currentFormat, current.sampleRate == sampleRate {
            return current
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        // Reconnect with new format
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log.audio.error("Failed to start AVAudioEngine: \(error.localizedDescription, privacy: .public)")
            }
        }
        currentFormat = format
        return format
    }
}
