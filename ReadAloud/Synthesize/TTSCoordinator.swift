import Foundation
import AVFoundation

/// Routes a `ReadRequest` to the right engine (Apple or sidecar) based on
/// user preferences and engine availability.
@MainActor
final class TTSCoordinator {
    private let appleEngine = AppleEngine()
    private let player = StreamingPlayer()
    private lazy var sidecarEngine = SidecarEngine(player: player)
    private let sidecar = SidecarController()

    private(set) var state: PlaybackState = .idle

    var onStateChange: ((PlaybackState) -> Void)?

    func speak(_ request: ReadRequest, preferences: PreferencesStore.Snapshot, rules: [PronunciationRule]) async {
        stop()
        update(.preparing)

        let processed = PronunciationStore.apply(rules, to: request.text, language: request.language)
        let engineChoice = preferences.engineByLanguage[request.language.rawValue] ?? .apple

        let resolvedEngine: EngineChoice
        if engineChoice == .sidecar, preferences.sidecarEnabled {
            var healthy = await sidecar.healthCheck()
            if !healthy { healthy = await sidecar.start() }
            resolvedEngine = healthy ? .sidecar : .apple
            if !healthy {
                Log.tts.notice("Sidecar unavailable; falling back to Apple voice")
            }
        } else {
            resolvedEngine = .apple
        }

        update(.speaking(progress: 0))

        switch resolvedEngine {
        case .apple:
            let voiceKey = "\(request.language.rawValue)|\(EngineChoice.apple.rawValue)"
            let voiceID = preferences.voiceByLanguageEngine[voiceKey]?.id
            await appleEngine.speak(
                processed,
                language: request.language,
                voiceID: voiceID,
                rate: preferences.rate,
                pitch: preferences.pitch
            )
        case .sidecar:
            let voiceKey = "\(request.language.rawValue)|\(EngineChoice.sidecar.rawValue)"
            let voiceID = preferences.voiceByLanguageEngine[voiceKey]?.id
                ?? defaultSidecarVoice(for: request.language)
            let modelID = sidecarModel(for: request.language)
            await sidecarEngine.speak(
                processed,
                language: request.language,
                voiceID: voiceID,
                modelID: modelID,
                rate: preferences.rate
            )
        }
        update(.idle)
    }

    func stop() {
        appleEngine.stop()
        sidecarEngine.stop()
        update(.idle)
    }

    func pause() {
        appleEngine.pause()
        player.pause()
        update(.paused)
    }

    func resume() {
        appleEngine.resume()
        player.resume()
        update(.speaking(progress: 0))
    }

    func warmUpSidecar() {
        Task { _ = await sidecar.start() }
    }

    private func update(_ newState: PlaybackState) {
        state = newState
        onStateChange?(newState)
    }

    private func defaultSidecarVoice(for language: SpokenLanguage) -> String {
        switch language {
        case .english: "af_heart"      // Kokoro default female voice
        case .polish:  "pl_speaker_01" // Chatterbox Polish reference (provided by sidecar)
        }
    }

    private func sidecarModel(for language: SpokenLanguage) -> String {
        switch language {
        case .english: "kokoro"
        case .polish:  "chatterbox"
        }
    }
}
