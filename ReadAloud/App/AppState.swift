import Foundation
import Observation
import SwiftUI
import AppKit

@MainActor
@Observable
final class AppState {
    /// Single instance shared between the SwiftUI scene, the hotkey bridge,
    /// and the AppDelegate. We use a singleton because the hotkey is registered
    /// before SwiftUI gets a chance to inject any environment.
    static let shared = AppState()

    // MARK: – Persisted preferences
    var preferences: PreferencesStore.Snapshot = PreferencesStore.load()
    var pronunciationRules: [PronunciationRule] = PronunciationStore.load()
    var perAppOverrides: [AppLanguageOverride] = PerAppOverridesStore.load()

    // MARK: – Runtime state
    var playbackState: PlaybackState = .idle
    var lastRead: ReadRequest?
    var lastError: String?
    var accessibilityTrusted: Bool = false
    var sidecarStatus: SidecarController.Status = .unknown

    // MARK: – Subsystems
    @ObservationIgnored private let coordinator = TTSCoordinator()
    @ObservationIgnored private let sidecar = SidecarController()
    @ObservationIgnored private var currentReadTask: Task<Void, Never>?

    init() {
        coordinator.onStateChange = { [weak self] state in
            self?.playbackState = state
        }
    }

    // MARK: – Lifecycle
    func bootstrap() async {
        accessibilityTrusted = SelectionService.ensureAccessibilityTrust(prompt: false)
        sidecarStatus = sidecar.isInstalled() ? .stopped : .notInstalled
        if preferences.sidecarEnabled && sidecar.isInstalled() {
            coordinator.warmUpSidecar()
        }
    }

    // MARK: – Read flow
    /// Entry point from the global hotkey. Captures selection, routes, and speaks.
    func handleReadHotkey() {
        Log.hotkey.notice("Read hotkey fired")
        currentReadTask?.cancel()
        currentReadTask = Task { [weak self] in
            guard let self else { return }
            // Re-check trust on every press — the user may have just granted it.
            self.accessibilityTrusted = SelectionService.ensureAccessibilityTrust(prompt: false)
            if !self.accessibilityTrusted {
                await self.flashError("Grant Accessibility permission to ReadAloud in System Settings")
                SelectionService.openAccessibilityPreferences()
                return
            }
            guard let capture = await SelectionService.capture() else {
                await self.flashError("No text selected (or the app didn't expose its selection)")
                return
            }
            let language = LanguageRouter.route(
                text: capture.text,
                sourceBundleID: capture.sourceBundleID,
                overrides: self.perAppOverrides
            )
            let request = ReadRequest(
                text: capture.text,
                language: language,
                sourceBundleID: capture.sourceBundleID,
                createdAt: .now
            )
            self.lastRead = request
            await self.coordinator.speak(
                request,
                preferences: self.preferences,
                rules: self.pronunciationRules
            )
        }
    }

    func handleStopHotkey() {
        stop()
    }

    /// Speaks a known-good test phrase. Bypasses selection capture so you can
    /// verify audio output is working independently of the AX path.
    func speakLiteral(_ language: SpokenLanguage) {
        Log.tts.notice("speakLiteral(\(language.rawValue, privacy: .public)) invoked")
        currentReadTask?.cancel()
        let text: String = switch language {
        case .english: "Hello. This is Read Aloud, ready to read your selection."
        case .polish:  "Cześć. To jest Read Aloud — gotowy do czytania zaznaczonego tekstu."
        }
        let request = ReadRequest(text: text, language: language, sourceBundleID: nil, createdAt: .now)
        lastRead = request
        currentReadTask = Task { [weak self] in
            guard let self else { return }
            Log.tts.notice("speakLiteral Task running")
            await self.coordinator.speak(request, preferences: self.preferences, rules: self.pronunciationRules)
            Log.tts.notice("speakLiteral Task done")
        }
    }

    /// Speaks whatever string is currently on the pasteboard.
    func speakPasteboard() {
        Log.tts.notice("speakPasteboard invoked")
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { await self.flashError("Pasteboard is empty") }
            return
        }
        let language = LanguageRouter.route(text: text, sourceBundleID: nil, overrides: perAppOverrides)
        let request = ReadRequest(text: text, language: language, sourceBundleID: nil, createdAt: .now)
        lastRead = request
        currentReadTask?.cancel()
        currentReadTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.speak(request, preferences: self.preferences, rules: self.pronunciationRules)
        }
    }

    func pause() { coordinator.pause() }
    func resume() { coordinator.resume() }
    func stop() {
        currentReadTask?.cancel()
        coordinator.stop()
    }

    var isSpeaking: Bool {
        if case .idle = playbackState { return false }
        return true
    }

    // MARK: – Preference mutations
    func setEngine(_ engine: EngineChoice, for language: SpokenLanguage) {
        preferences.engineByLanguage[language.rawValue] = engine
        PreferencesStore.save(preferences)
    }

    func setVoice(_ voice: VoiceSelection, for language: SpokenLanguage, engine: EngineChoice) {
        preferences.voiceByLanguageEngine["\(language.rawValue)|\(engine.rawValue)"] = voice
        PreferencesStore.save(preferences)
    }

    func setRate(_ rate: Float) {
        preferences.rate = rate
        PreferencesStore.save(preferences)
    }

    func setPitch(_ pitch: Float) {
        preferences.pitch = pitch
        PreferencesStore.save(preferences)
    }

    func setSidecarEnabled(_ enabled: Bool) {
        preferences.sidecarEnabled = enabled
        PreferencesStore.save(preferences)
        if enabled { coordinator.warmUpSidecar() }
    }

    // MARK: – Pronunciation rules
    func addPronunciationRule(_ rule: PronunciationRule) {
        pronunciationRules.append(rule)
        PronunciationStore.save(pronunciationRules)
    }

    func removePronunciationRules(_ ids: Set<UUID>) {
        pronunciationRules.removeAll { ids.contains($0.id) }
        PronunciationStore.save(pronunciationRules)
    }

    // MARK: – Per-app overrides
    func addOverride(_ rule: AppLanguageOverride) {
        perAppOverrides.removeAll { $0.bundleID == rule.bundleID }
        perAppOverrides.append(rule)
        PerAppOverridesStore.save(perAppOverrides)
    }

    func removeOverrides(_ ids: Set<UUID>) {
        perAppOverrides.removeAll { ids.contains($0.id) }
        PerAppOverridesStore.save(perAppOverrides)
    }

    // MARK: – Errors
    private func flashError(_ message: String) async {
        lastError = message
        Log.app.notice("\(message, privacy: .public)")
        NSSound.beep()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if lastError == message { lastError = nil }
    }
}
