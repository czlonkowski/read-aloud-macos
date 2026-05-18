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

    /// Voices for the given language, excluding the macOS novelty voices
    /// (Albert, Bahh, Bells, Bubbles, Zarvox, etc.) that are unsuited to
    /// reading prose. Sorted so Premium > Enhanced > Default, then by name.
    static func availableVoices(for language: SpokenLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.bcp47.prefix(2)) }
            .filter { !isNoveltyVoice($0) }
            .sorted { lhs, rhs in
                // Exact-locale match wins (en-US before en-GB).
                let lhsExact = (lhs.language == language.bcp47)
                let rhsExact = (rhs.language == language.bcp47)
                if lhsExact != rhsExact { return lhsExact }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    /// The voice we'll use when the user hasn't picked one explicitly.
    ///
    /// Trusts the system's preferred voice for the locale (Samantha for
    /// en-US, Zosia for pl-PL on a stock macOS) and only overrides it when
    /// the user has actually installed something with a strictly higher
    /// quality tier — typically an Enhanced or Premium voice via
    /// System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voices.
    ///
    /// This avoids picking alphabetically-first oddities like Eddy or Albert
    /// over Samantha when everything is tied at default quality.
    static func bestVoice(for language: SpokenLanguage) -> AVSpeechSynthesisVoice? {
        let systemDefault = AVSpeechSynthesisVoice(language: language.bcp47)
        let curated = availableVoices(for: language)
        if let systemDefault, let top = curated.first,
           top.quality.rawValue > systemDefault.quality.rawValue {
            return top
        }
        return systemDefault ?? curated.first
    }

    /// The legacy `com.apple.speech.synthesis.voice.*` identifiers cover all
    /// the macOS "novelty" voices (Albert, Bahh, Bells, Boing, Bubbles,
    /// Cellos, Wobble, Fred, GoodNews, BadNews, Jester, Junior, Kathy, Organ,
    /// Superstar, Ralph, Trinoids, Whisper, Zarvox). None of them are good for
    /// reading long-form prose, and several have missing audio assets on
    /// recent macOS — picking them produces silent "successful" speech.
    private static func isNoveltyVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
    }

    /// Speaks `text` and resumes when playback completes (or is cancelled).
    func speak(
        _ text: String,
        language: SpokenLanguage,
        voiceID: String?,
        rate: Float,
        pitch: Float
    ) async {
        Log.tts.notice("AppleEngine.speak entered, text.count=\(text.count, privacy: .public)")
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

        Log.tts.notice("AppleEngine voice=\(utterance.voice?.identifier ?? "nil", privacy: .public) rate=\(utterance.rate, privacy: .public)")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            Log.tts.notice("AppleEngine calling synth.speak()")
            synth.speak(utterance)
        }
        Log.tts.notice("AppleEngine.speak finished")
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
