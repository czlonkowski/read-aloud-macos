import Foundation
import AVFoundation

/// Wraps `AVSpeechSynthesizer` so it presents the same async-cancellable API
/// surface as the sidecar engine.
@MainActor
final class AppleEngine: NSObject {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isCancelled = false

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Lists the highest-quality voice per locale code installed on this Mac.
    /// Sorted so Premium > Enhanced > Default within each language.
    static func availableVoices(for language: SpokenLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.bcp47.prefix(2)) }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    /// The voice the system would prefer for this language at the highest installed quality.
    static func bestVoice(for language: SpokenLanguage) -> AVSpeechSynthesisVoice? {
        availableVoices(for: language).first
    }

    /// Speaks `text` and resumes when playback completes (or is cancelled).
    func speak(
        _ text: String,
        language: SpokenLanguage,
        voiceID: String?,
        rate: Float,
        pitch: Float
    ) async {
        // Cancel anything currently speaking.
        if synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
        isCancelled = false

        let utterance = AVSpeechUtterance(string: text)
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.bestVoice(for: language)
                ?? AVSpeechSynthesisVoice(language: language.bcp47)
        }
        utterance.rate = clampRate(rate)
        utterance.pitchMultiplier = max(0.5, min(2.0, pitch))

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            synth.speak(utterance)
        }
    }

    func pause() {
        synth.pauseSpeaking(at: .word)
    }

    func resume() {
        synth.continueSpeaking()
    }

    func stop() {
        isCancelled = true
        synth.stopSpeaking(at: .immediate)
    }

    private func clampRate(_ rate: Float) -> Float {
        // AVSpeechUtteranceMinimumSpeechRate is 0.0, Maximum is 1.0; Default ~0.5.
        max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
    }
}

extension AppleEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}
