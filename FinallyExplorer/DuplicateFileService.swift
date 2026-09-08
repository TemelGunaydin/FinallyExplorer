import Foundation

nonisolated protocol DuplicateFinding: Sendable {
    func scan(rootURL: URL, includesHidden: Bool, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> DuplicateScanSnapshot
}

nonisolated struct DuplicateFileService: DuplicateFinding {
    var entryLimit = 50_000

    @concurrent
    func scan(
        rootURL: URL, includesHidden: Bool = false,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async throws -> DuplicateScanSnapshot {
        try Task.checkCancellation()
        let url = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path != "/", (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else {
            throw FolderComparisonError.invalidFolders
        }
        let root = try ScopedFolderDescriptor(rootURL: url)
        let rootState = try root.state()
        var (entries, excluded) = try await FolderTreeScanner.scan(
            root, rootURL: url, includesHidden: includesHidden, entryLimit: entryLimit, progress: progress
        )
        var bySize: [Int64: [ComparedFolderEntry]] = [:]
        for var entry in entries.values where entry.state.isRegularFile && entry.skippedReason == nil {
            if entry.state.size == 0 { entry.skippedReason = "Empty file — no duplicate data" }
            else if entry.state.linkCount != 1 { entry.skippedReason = "Hard-linked file — excluded" }
            else { bySize[entry.state.size, default: []].append(entry) }
            entries[entry.relativePath] = entry
        }
        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }.sorted { $0.relativePath < $1.relativePath }
        var total: Int64 = 0
        for entry in candidates {
            let sum = total.addingReportingOverflow(entry.state.size)
            guard sum.overflow == false, entry.state.size > 0 else { throw FolderComparisonError.limitExceeded }
            total = sum.partialValue
        }
        var byHash: [Data: [ComparedFolderEntry]] = [:]
        var bytes: Int64 = 0, hashed = 0
        for (index, entry) in candidates.enumerated() {
            try Task.checkCancellation()
            let file: ScopedFolderDescriptor
            do { file = try DuplicateFileVerifier.open(entry, root: root) }
            catch {
                entries[entry.relativePath]?.skippedReason = error.localizedDescription
                continue
            }
            let completed = bytes, byteTotal = total
            let hash = try await ComparedFileHasher.digest(file, expected: entry.state, path: entry.relativePath) { value in
                await progress(FolderWorkProgress(phase: "Checking duplicate candidates…", relativePath: entry.relativePath,
                    completedItems: index, totalItems: candidates.count, completedBytes: completed + value, totalBytes: byteTotal))
            }
            var verified = entry
            verified.sha256 = hash
            entries[entry.relativePath] = verified
            byHash[hash, default: []].append(verified)
            bytes += entry.state.size
            hashed += 1
        }
        var groups: [DuplicateGroup] = []
        for (hash, files) in byHash where files.count > 1 {
            guard let first = files.first else { continue }
            var matching = [first]
            for file in files.dropFirst() {
                await progress(FolderWorkProgress(phase: "Verifying byte-for-byte matches…", relativePath: file.relativePath))
                if try DuplicateFileVerifier.equalData(first, file, root: root) { matching.append(file) }
                else { entries[file.relativePath]?.skippedReason = "File data differs despite matching hash — excluded" }
            }
            if matching.count > 1 {
                groups.append(DuplicateGroup(id: hash.base64EncodedString(), files: matching, fileSize: first.state.size))
            }
        }
        try FolderTreeScanner.validate(root, root: rootState, entries: entries)
        // Reject a moved/replaced selected root, not just changed child entries.
        guard try ScopedFolderDescriptor(rootURL: url).state().hasSameIdentity(as: rootState) else { throw FolderComparisonError.changed(url.path) }
        groups.sort { $0.duplicateBytes == $1.duplicateBytes ? $0.id < $1.id : $0.duplicateBytes > $1.duplicateBytes }
        return DuplicateScanSnapshot(rootURL: url, rootState: rootState, entries: entries, groups: groups,
            skipped: entries.values.filter { $0.skippedReason != nil }.sorted { $0.relativePath < $1.relativePath },
            excludedHiddenCount: excluded, hashedFileCount: hashed, duplicateBytes: groups.reduce(0) { $0 + $1.duplicateBytes })
    }
}
