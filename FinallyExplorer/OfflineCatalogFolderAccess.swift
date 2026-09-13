import Darwin
import Foundation

nonisolated enum OfflineCatalogFolderAccess {
    /// Inspect ancestors with metadata-only operations; opening their directory
    /// contents would require a broader grant than the user-selected subfolder.
    /// Validate every component before and after opening the selected root so a
    /// symlink replacement cannot redirect a saved catalog into another tree.
    static func openSelectedFolder(_ rootURL: URL, in volumeURL: URL) throws -> ScopedFolderDescriptor {
        let relative = try OfflineCatalogValidation.relativePath(of: rootURL, in: volumeURL)
        let components = relative.isEmpty ? [] : try ScopedFolderDescriptor.components(relative)
        var paths = [volumeURL]
        for component in components { paths.append(paths[paths.count - 1].appending(path: component)) }
        let before = try paths.map(directoryMetadata)
        let root = try ScopedFolderDescriptor(rootURL: rootURL)
        let opened = try root.state()
        guard let first = before.first, let last = before.last,
              opened.hasSameIdentity(as: last), before.allSatisfy({ $0.device == first.device }) else {
            throw OfflineCatalogError.changedItem
        }
        for (path, expected) in zip(paths, before) {
            try Task.checkCancellation()
            guard try directoryMetadata(path).hasSameIdentity(as: expected) else { throw OfflineCatalogError.changedItem }
        }
        return root
    }

    static func directoryMetadata(_ url: URL) throws -> ComparedFileState {
        guard FolderAccessBookmark.isLocalURL(url) else { throw OfflineCatalogError.invalidSource }
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw FolderComparisonError.fileSystem(url.path, errno) }
        let state = ComparedFileState(value)
        guard state.isDirectory, state.isPlaceholder == false, state.inode > 0 else { throw OfflineCatalogError.invalidSource }
        return state
    }
}
