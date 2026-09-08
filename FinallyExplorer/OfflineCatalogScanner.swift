import Foundation

nonisolated struct OfflineCatalogScanner: OfflineCatalogScanning {
    let volumes: any OfflineVolumeAccessing
    var entryLimit = OfflineCatalogValidation.entryLimit
    var pathByteLimit = OfflineCatalogValidation.pathByteLimit

    @concurrent func scan(_ selected: OfflineCatalogSource, includesHidden: Bool,
                         progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> OfflineCatalogSnapshot {
        try Task.checkCancellation()
        let source = try await volumes.source(for: selected.rootURL)
        guard source.volume.id == selected.volume.id, source.rootInode == selected.rootInode else { throw OfflineCatalogError.changedItem }
        let root = try ScopedFolderDescriptor(rootURL: source.rootURL)
        let initial = try root.state()
        guard initial.inode == source.rootInode else { throw OfflineCatalogError.changedItem }
        let (entries, excluded) = try await FolderTreeScanner.scan(root, rootURL: source.rootURL, includesHidden: includesHidden,
            entryLimit: entryLimit, pathByteLimit: pathByteLimit, progress: progress)
        await progress(FolderWorkProgress(phase: "Checking catalog snapshot…", relativePath: source.rootURL.path, completedItems: entries.count))
        try FolderTreeScanner.validate(root, root: initial, entries: entries)
        let current = try await volumes.source(for: source.rootURL)
        guard current.volume.id == source.volume.id, current.rootInode == source.rootInode else { throw OfflineCatalogError.changedItem }
        try Task.checkCancellation()
        let eligible = entries.values.filter { $0.skippedReason == nil }.sorted { $0.relativePath < $1.relativePath }
        let rows = eligible.map { entry in
            OfflineCatalogEntry(relativePath: entry.relativePath, isDirectory: entry.state.isDirectory,
                byteCount: entry.state.isDirectory ? nil : entry.state.size,
                modifiedAt: Date(timeIntervalSince1970: Double(entry.state.modifiedSeconds) + Double(entry.state.modifiedNanoseconds) / 1_000_000_000),
                inode: entry.state.inode)
        }
        let summary = OfflineCatalogSummary(id: UUID(), volumeID: source.volume.id, volumeName: source.volume.name,
            relativeRoot: source.relativeRoot, rootInode: source.rootInode, scannedAt: .now, includesHidden: includesHidden,
            entryCount: rows.count, skippedCount: entries.count - rows.count, excludedHiddenCount: excluded)
        let snapshot = OfflineCatalogSnapshot(summary: summary, entries: rows)
        try snapshot.validate()
        return snapshot
    }
}
