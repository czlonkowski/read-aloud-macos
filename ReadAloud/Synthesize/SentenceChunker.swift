import Foundation
import NaturalLanguage

enum SentenceChunker {
    /// Splits text into sentence-sized chunks suitable for streaming TTS.
    /// Short sentences are joined so we don't pay per-request overhead for
    /// utterances under ~80 characters.
    static func chunks(from text: String, minChars: Int = 80, maxChars: Int = 600) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let s = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty { return [trimmed] }

        var out: [String] = []
        var buffer = ""
        for s in sentences {
            if buffer.isEmpty {
                buffer = s
            } else if buffer.count + 1 + s.count <= maxChars && buffer.count < minChars {
                buffer += " " + s
            } else if buffer.count < minChars {
                buffer += " " + s
            } else {
                out.append(buffer)
                buffer = s
            }
        }
        if !buffer.isEmpty { out.append(buffer) }
        return out
    }
}
