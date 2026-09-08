import Foundation

nonisolated enum OfflineCatalogSearch {
    @concurrent static func search(_ entries: [OfflineCatalogEntry], query: OfflineCatalogQuery,
                                   limit: Int = 200) async throws -> OfflineCatalogSearchResult {
        let words = query.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let suffix = query.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        var rows: [OfflineCatalogEntry] = [], count = 0
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 100) { try Task.checkCancellation() }
            guard words.allSatisfy({ entry.relativePath.localizedStandardContains($0) }),
                  suffix.isEmpty || (entry.isDirectory == false && URL(filePath: entry.relativePath).pathExtension.lowercased() == suffix),
                  query.minimumBytes <= 0 || (entry.byteCount ?? -1) >= query.minimumBytes,
                  query.modifiedSince.map({ entry.modifiedAt >= $0 }) ?? true else { continue }
            count += 1
            if rows.count < max(0, limit) { rows.append(entry) }
        }
        try Task.checkCancellation()
        return OfflineCatalogSearchResult(entries: rows, totalMatches: count)
    }
}
