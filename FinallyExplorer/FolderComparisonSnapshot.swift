import Foundation

nonisolated struct FolderComparisonSnapshot: Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let sourceRoot: ComparedFileState
    let destinationRoot: ComparedFileState
    let sourceEntries: [String: ComparedFolderEntry]
    let destinationEntries: [String: ComparedFolderEntry]
    let rows: [FolderComparisonRow]
    let includesHidden: Bool
    let excludedHiddenCount: Int

    var missingEntries: [ComparedFolderEntry] {
        rows.compactMap { row in
            guard row.status == .onlySource, let source = row.source,
                  source.skippedReason == nil else { return nil }
            let parents = source.relativePath.split(separator: "/").dropLast()
            var path = ""
            for name in parents {
                path = path.isEmpty ? String(name) : path + "/" + name
                if let entry = destinationEntries[path], entry.state.isDirectory == false || entry.skippedReason != nil {
                    return nil
                }
            }
            return source
        }
    }
}
