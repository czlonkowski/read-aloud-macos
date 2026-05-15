import SwiftUI
import AVFoundation

struct VoicePickerView: View {
    let language: SpokenLanguage
    @Environment(AppState.self) private var state

    var body: some View {
        let engine = state.preferences.engineByLanguage[language.rawValue] ?? .apple

        let engineBinding = Binding<EngineChoice>(
            get: { engine },
            set: { state.setEngine($0, for: language) }
        )

        VStack(alignment: .leading, spacing: 12) {
            Picker("Engine", selection: engineBinding) {
                ForEach(EngineChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            switch engine {
            case .apple:
                applePicker
            case .sidecar:
                sidecarPicker
            }
        }
    }

    @ViewBuilder
    private var applePicker: some View {
        let voices = AppleEngine.availableVoices(for: language)
        if voices.isEmpty {
            Text("No Apple voices installed for \(language.displayName).")
                .foregroundStyle(.secondary)
            Button("Open System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Speech") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            let currentID = state.preferences.voiceByLanguageEngine["\(language.rawValue)|\(EngineChoice.apple.rawValue)"]?.id
                ?? voices.first?.identifier
                ?? ""
            let voiceBinding = Binding<String>(
                get: { currentID },
                set: { newID in
                    guard let voice = voices.first(where: { $0.identifier == newID }) else { return }
                    state.setVoice(
                        VoiceSelection(id: voice.identifier, displayName: voice.name),
                        for: language,
                        engine: .apple
                    )
                }
            )
            Picker("Voice", selection: voiceBinding) {
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) — \(qualityLabel(voice.quality))").tag(voice.identifier)
                }
            }
            Text("Higher-quality voices download from System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sidecarPicker: some View {
        let voices = SidecarVoiceLibrary.voices(for: language)
        let currentID = state.preferences.voiceByLanguageEngine["\(language.rawValue)|\(EngineChoice.sidecar.rawValue)"]?.id
            ?? voices.first?.id
            ?? ""
        let voiceBinding = Binding<String>(
            get: { currentID },
            set: { newID in
                guard let voice = voices.first(where: { $0.id == newID }) else { return }
                state.setVoice(voice, for: language, engine: .sidecar)
            }
        )
        Picker("Voice", selection: voiceBinding) {
            ForEach(voices, id: \.id) { voice in
                Text(voice.displayName).tag(voice.id)
            }
        }
        if !state.preferences.sidecarEnabled {
            Text("Enable the neural sidecar from the Neural tab to use these voices.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium:  "Premium"
        case .enhanced: "Enhanced"
        default:        "Default"
        }
    }
}

enum SidecarVoiceLibrary {
    /// Hardcoded for v0.1; later this will be fetched from the sidecar's
    /// `/v1/voices` endpoint so reference clips added by the user appear here.
    static func voices(for language: SpokenLanguage) -> [VoiceSelection] {
        switch language {
        case .english:
            return [
                VoiceSelection(id: "af_heart", displayName: "Heart (Kokoro)"),
                VoiceSelection(id: "af_bella", displayName: "Bella (Kokoro)"),
                VoiceSelection(id: "am_michael", displayName: "Michael (Kokoro)"),
                VoiceSelection(id: "am_adam", displayName: "Adam (Kokoro)")
            ]
        case .polish:
            return [
                VoiceSelection(id: "pl_speaker_01", displayName: "Reference 1 (Chatterbox PL)"),
                VoiceSelection(id: "pl_speaker_02", displayName: "Reference 2 (Chatterbox PL)")
            ]
        }
    }
}
