import Foundation

nonisolated enum VisualSearchMode: String, CaseIterable, Identifiable, Sendable {
    case both = "Labels & Text", labels = "Visual Labels", text = "Text in Images"
    var id: Self { self }
}

nonisolated struct VisualSearchMatch: Identifiable, Sendable {
    var id: String { entry.id }
    let entry: VisualSearchSnapshot.Entry
    let labels: [String]
    let excerpt: String?
}

nonisolated enum VisualSearchQuery {
    /// All query words must match observed labels/OCR, never filenames or paths.
    @concurrent static func search(_ entries: [VisualSearchSnapshot.Entry], query: String,
                                   mode: VisualSearchMode) async throws -> [VisualSearchMatch] {
        guard query.count <= 200 else { throw VisualSearchError.queryTooLong }
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        var matches: [VisualSearchMatch] = []
        for entry in entries {
            try Task.checkCancellation()
            let labels = mode == .text ? [] : entry.evidence.labels.map(\.name)
            let text = mode == .labels ? "" : entry.evidence.text
            if mode == .text && text.isEmpty { continue }
            if mode == .labels && labels.isEmpty { continue }
            let normalizedLabels = labels.map(normalize)
            let normalizedText = normalize(text)
            guard tokens.allSatisfy({ token in
                normalizedLabels.contains { $0.contains(token) } || normalizedText.contains(token)
            }) else { continue }
            let matchingLabels = tokens.isEmpty ? labels : labels.filter { label in tokens.contains { normalize(label).contains($0) } }
            let matchingText = tokens.isEmpty || tokens.contains { normalizedText.contains($0) }
            matches.append(VisualSearchMatch(entry: entry, labels: matchingLabels,
                excerpt: matchingText && text.isEmpty == false ? excerpt(text, tokens: tokens) : nil))
        }
        return matches
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func excerpt(_ text: String, tokens: [String]) -> String {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let position = tokens.compactMap { text.range(of: $0, options: options)?.lowerBound }.min() ?? text.startIndex
        let start = text.index(position, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(start, offsetBy: 240, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }
}
