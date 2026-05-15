import Foundation

struct AppLanguageOverride: Codable, Identifiable, Hashable {
    var id: UUID
    var bundleID: String
    var language: SpokenLanguage

    init(id: UUID = UUID(), bundleID: String, language: SpokenLanguage) {
        self.id = id
        self.bundleID = bundleID
        self.language = language
    }
}

enum PerAppOverridesStore {
    private static let filename = "per-app-overrides.json"

    static func load() -> [AppLanguageOverride] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AppLanguageOverride].self, from: data)) ?? []
    }

    static func save(_ rules: [AppLanguageOverride]) {
        guard let url = fileURL() else { return }
        try? JSONEncoder().encode(rules).write(to: url, options: .atomic)
    }

    static func languageOverride(for bundleID: String?, in rules: [AppLanguageOverride]) -> SpokenLanguage? {
        guard let bundleID else { return nil }
        return rules.first(where: { $0.bundleID == bundleID })?.language
    }

    private static func fileURL() -> URL? {
        PreferencesStore.applicationSupportURL()?.appendingPathComponent(filename)
    }
}
