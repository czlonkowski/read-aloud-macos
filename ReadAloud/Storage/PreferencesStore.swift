import Foundation

/// Persists user preferences in JSON under `~/Library/Application Support/ReadAloud/`.
/// Mirrors the per-feature Store pattern from MeetingTranscriber.
enum PreferencesStore {
    struct Snapshot: Codable {
        var engineByLanguage: [String: EngineChoice]
        var voiceByLanguageEngine: [String: VoiceSelection] // key: "<lang>|<engine>"
        var rate: Float
        var pitch: Float
        var sidecarEnabled: Bool

        static let defaults = Snapshot(
            engineByLanguage: [
                SpokenLanguage.english.rawValue: .apple,
                SpokenLanguage.polish.rawValue:  .apple
            ],
            voiceByLanguageEngine: [:],
            rate: 0.5,        // AVSpeechUtteranceDefaultSpeechRate
            pitch: 1.0,
            sidecarEnabled: false
        )
    }

    private static let filename = "preferences.json"

    static func load() -> Snapshot {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else {
            return .defaults
        }
        return (try? JSONDecoder().decode(Snapshot.self, from: data)) ?? .defaults
    }

    static func save(_ snapshot: Snapshot) {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.app.error("PreferencesStore.save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func fileURL() -> URL? {
        guard let base = applicationSupportURL() else { return nil }
        return base.appendingPathComponent(filename)
    }

    static func applicationSupportURL() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("ReadAloud", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
