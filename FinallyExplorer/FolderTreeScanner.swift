import Foundation

/// Shared read-only enumeration policy for comparison and file tools.
/// No child links, packages, nested mounts or cloud placeholders are followed.
nonisolated enum FolderTreeScanner {
    static func scan(
        _ root: ScopedFolderDescriptor, rootURL: URL, includesHidden: Bool,
        entryLimit: Int = 50_000, recursive: Bool = true,
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
                // Do not merge distinct, canonically equivalent names on unusual filesystems.
                guard entries[path] == nil else { throw FolderComparisonError.changed(path) }
                let isPackage = state.isDirectory && (
                    (try? rootURL.appending(path: path).resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                )
                let reason: String?
                if state.isPlaceholder { reason = "Cloud placeholder — download it first" }
                else if state.device != device { reason = "Mounted subfolder — scan it separately" }
                else if isPackage { reason = "Package — contents not inspected" }
                else if state.isRegularFile == false && state.isDirectory == false { reason = "Link or special file — not followed" }
                else { reason = nil }
                entries[path] = ComparedFolderEntry(relativePath: path, state: state, sha256: nil, skippedReason: reason)
                if recursive, state.isDirectory, reason == nil { directories.append(components + [name]) }
                if entries.count.isMultiple(of: 100) {
                    await progress(FolderWorkProgress(phase: "Reading folder…", relativePath: path, completedItems: entries.count))
                }
            }
        }
        return (entries, excluded)
    }

    static func validate(_ folder: ScopedFolderDescriptor, root: ComparedFileState, entries: [String: ComparedFolderEntry]) throws {
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
