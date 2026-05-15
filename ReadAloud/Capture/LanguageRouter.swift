import Foundation
import NaturalLanguage

enum LanguageRouter {
    /// Picks a `SpokenLanguage` for the captured text. Per-app overrides win over
    /// content-based detection. If detection is uncertain, falls back to `.english`.
    static func route(
        text: String,
        sourceBundleID: String?,
        overrides: [AppLanguageOverride]
    ) -> SpokenLanguage {
        if let forced = PerAppOverridesStore.languageOverride(for: sourceBundleID, in: overrides) {
            return forced
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return .english }
        switch dominant {
        case .polish:  return .polish
        case .english: return .english
        default:       return .english
        }
    }
}
