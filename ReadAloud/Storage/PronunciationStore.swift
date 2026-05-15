import Foundation

struct PronunciationRule: Codable, Identifiable, Hashable {
    var id: UUID
    var pattern: String     // case-insensitive literal match
    var replacement: String
    var language: SpokenLanguage?  // nil = applies to all

    init(id: UUID = UUID(), pattern: String, replacement: String, language: SpokenLanguage? = nil) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.language = language
    }
}

enum PronunciationStore {
    private static let filename = "pronunciation.json"

    static func load() -> [PronunciationRule] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PronunciationRule].self, from: data)) ?? []
    }

    static func save(_ rules: [PronunciationRule]) {
        guard let url = fileURL() else { return }
        try? JSONEncoder().encode(rules).write(to: url, options: .atomic)
    }

    static func apply(_ rules: [PronunciationRule], to text: String, language: SpokenLanguage) -> String {
        var out = text
        for rule in rules where rule.language == nil || rule.language == language {
            out = out.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: .caseInsensitive)
        }
        return out
    }

    private static func fileURL() -> URL? {
        PreferencesStore.applicationSupportURL()?.appendingPathComponent(filename)
    }
}
