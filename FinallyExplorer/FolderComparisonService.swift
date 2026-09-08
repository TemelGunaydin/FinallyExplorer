import Foundation

nonisolated protocol FolderComparing: Sendable {
    func compare(
        source: URL, destination: URL, includesHidden: Bool,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void
    ) async throws -> FolderComparisonSnapshot
}

nonisolated struct FolderComparisonService: FolderComparing {
    var entryLimit = 50_000

    @concurrent
    func compare(
        source: URL, destination: URL, includesHidden: Bool = false,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async throws -> FolderComparisonSnapshot {
        try Task.checkCancellation()
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        try Self.validateRoots(source, destination)
        let sourceFolder = try ScopedFolderDescriptor(rootURL: source)
        let destinationFolder = try ScopedFolderDescriptor(rootURL: destination)
        let sourceRoot = try sourceFolder.state()
        let destinationRoot = try destinationFolder.state()
        guard try sourceFolder.containsDirectory(destinationFolder) == false,
              try destinationFolder.containsDirectory(sourceFolder) == false else { throw FolderComparisonError.overlappingFolders }
        let left = try await scan(sourceFolder, rootURL: source, includesHidden: includesHidden, progress: progress)
        let right = try await scan(destinationFolder, rootURL: destination, includesHidden: includesHidden, progress: progress)
        var rows: [FolderComparisonRow] = []
        for path in Set(left.entries.keys).union(right.entries.keys).sorted() {
            try Task.checkCancellation()
            let a = left.entries[path], b = right.entries[path]
            let status: FolderComparisonRow.Status
            if a?.skippedReason != nil || b?.skippedReason != nil { status = .skipped }
            else if a == nil { status = .onlyDestination }
            else if b == nil { status = .onlySource }
            else if a?.state.isDirectory != b?.state.isDirectory { status = .conflict }
            else if a?.state.isDirectory == true { status = .folder }
            else { status = a?.sha256 == b?.sha256 ? .same : .different }
            rows.append(FolderComparisonRow(relativePath: path, source: a, destination: b, status: status))
        }
        // A changing tree must not produce an actionable, apparently complete snapshot.
        try validateTree(sourceFolder, root: sourceRoot, entries: left.entries)
        try validateTree(destinationFolder, root: destinationRoot, entries: right.entries)
        return FolderComparisonSnapshot(
            sourceURL: source, destinationURL: destination, sourceRoot: sourceRoot, destinationRoot: destinationRoot,
            sourceEntries: left.entries, destinationEntries: right.entries, rows: rows,
            includesHidden: includesHidden, excludedHiddenCount: left.excluded + right.excluded
        )
    }

    static func validateRoots(_ source: URL, _ destination: URL) throws {
        let a = source.path, b = destination.path
        guard a != b, a != "/", b != "/", a.hasPrefix(b + "/") == false,
              b.hasPrefix(a + "/") == false else { throw FolderComparisonError.overlappingFolders }
    }

    private func scan(
        _ root: ScopedFolderDescriptor, rootURL: URL, includesHidden: Bool,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void
    ) async throws -> (entries: [String: ComparedFolderEntry], excluded: Int) {
        var (entries, excluded) = try await FolderTreeScanner.scan(
            root, rootURL: rootURL, includesHidden: includesHidden, entryLimit: entryLimit, progress: progress
        )
        let files = entries.values.filter { $0.state.isRegularFile && $0.skippedReason == nil }.sorted { $0.relativePath < $1.relativePath }
        var totalBytes: Int64 = 0
        for entry in files {
            let next = totalBytes.addingReportingOverflow(entry.state.size)
            guard next.overflow == false, entry.state.size >= 0 else { throw FolderComparisonError.limitExceeded }
            totalBytes = next.partialValue
        }
        var completedBytes: Int64 = 0
        for (index, entry) in files.enumerated() {
            let names = try ScopedFolderDescriptor.components(entry.relativePath)
            let parent = try root.directory(Array(names.dropLast()))
            let file = try parent.openFile(names[names.count - 1])
            let previousBytes = completedBytes, byteCount = totalBytes
            let hash = try await ComparedFileHasher.digest(file, expected: entry.state, path: entry.relativePath) { bytes in
                await progress(FolderWorkProgress(
                    phase: "Comparing file data…", relativePath: entry.relativePath,
                    completedItems: index, totalItems: files.count,
                    completedBytes: previousBytes + bytes, totalBytes: byteCount
                ))
            }
            entries[entry.relativePath]?.sha256 = hash
            completedBytes += entry.state.size
        }
        return (entries, excluded)
    }

    private func validateTree(_ folder: ScopedFolderDescriptor, root: ComparedFileState, entries: [String: ComparedFolderEntry]) throws {
        try FolderTreeScanner.validate(folder, root: root, entries: entries)
    }
}
