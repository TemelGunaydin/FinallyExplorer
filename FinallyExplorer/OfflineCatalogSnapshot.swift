import Foundation

nonisolated struct OfflineCatalogSnapshot: Codable, Sendable {
    let summary: OfflineCatalogSummary
    let entries: [OfflineCatalogEntry]

    func validate() throws {
        try summary.validate()
        guard summary.entryCount == entries.count else { throw OfflineCatalogError.invalidCatalog }
        var paths: Set<String> = []
        var pathBytes = 0
        for entry in entries {
            try Task.checkCancellation()
            try OfflineCatalogValidation.path(entry.relativePath)
            pathBytes += entry.relativePath.utf8.count
            guard paths.insert(entry.relativePath).inserted, entry.inode > 0,
                  entry.modifiedAt.timeIntervalSince1970.isFinite,
                  entry.isDirectory ? entry.byteCount == nil : (entry.byteCount ?? -1) >= 0,
                  pathBytes <= OfflineCatalogValidation.pathByteLimit else { throw OfflineCatalogError.invalidCatalog }
        }
    }
}
