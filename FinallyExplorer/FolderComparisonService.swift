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
        var entries: [String: ComparedFolderEntry] = [:]
        var directories: [[String]] = [[]]
        var excluded = 0
        let device = try root.state().device
        await progress(FolderWorkProgress(phase: "Reading folder…", relativePath: rootURL.path))
        while let components = directories.popLast() {
            try Task.checkCancellation()
            guard components.count < 64 else { throw FolderComparisonError.limitExceeded }
            let folder = try root.directory(components)
            for name in try folder.names(limit: entryLimit - entries.count) {
                try Task.checkCancellation()
                guard let state = try folder.state(of: name) else { throw FolderComparisonError.changed(name) }
                if includesHidden == false, name.hasPrefix(".") || state.isHidden { excluded += 1; continue }
                let path = (components + [name]).joined(separator: "/")
                // Swift strings compare canonical Unicode equivalents as equal.
                // Do not silently merge distinct directory entries on unusual filesystems.
                guard entries[path] == nil else { throw FolderComparisonError.changed(path) }
                let isPackage = state.isDirectory && (
                    (try? rootURL.appending(path: path).resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                )
                let reason: String?
                if state.isPlaceholder { reason = "Cloud placeholder — download it first" }
                else if state.device != device { reason = "Mounted subfolder — compare it separately" }
                else if isPackage { reason = "Package — use normal copy" }
                else if state.isRegularFile == false && state.isDirectory == false { reason = "Link or special file — not followed" }
                else { reason = nil }
                entries[path] = ComparedFolderEntry(relativePath: path, state: state, sha256: nil, skippedReason: reason)
                if state.isDirectory, reason == nil { directories.append(components + [name]) }
                if entries.count.isMultiple(of: 100) {
                    await progress(FolderWorkProgress(phase: "Reading folder…", relativePath: path, completedItems: entries.count))
                }
            }
        }
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
        guard try folder.state() == root else { throw FolderComparisonError.changed("Folder contents") }
        for entry in entries.values {
            try Task.checkCancellation()
            let names = try ScopedFolderDescriptor.components(entry.relativePath)
            let parent = try folder.directory(Array(names.dropLast()))
            guard try parent.state(of: names[names.count - 1]) == entry.state else {
                throw FolderComparisonError.changed(entry.relativePath)
            }
        }
    }
}
