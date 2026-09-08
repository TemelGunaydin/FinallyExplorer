import Foundation

nonisolated struct LocalOfflineVolumeAccess: OfflineVolumeAccessing {
    /// Injected only by isolated UI fixtures; live discovery never trusts a disk's name.
    var fixtureVolumes: [OfflineCatalogVolume]?

    @concurrent func volumes() async throws -> [OfflineCatalogVolume] {
        try Task.checkCancellation()
        if let fixtureVolumes {
            return fixtureVolumes.filter { (try? ScopedFolderDescriptor(rootURL: $0.rootURL)) != nil }
        }
        return MountedVolume.discover().filter(\.shouldAppearInSidebar).compactMap { volume in
            let url = volume.url.resolvingSymlinksInPath().standardizedFileURL
            guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsLocalKey]),
                  values.volumeIsLocal == true, let rawID = values.volumeUUIDString,
                  let id = UUID(uuidString: rawID) else { return nil }
            return OfflineCatalogVolume(id: id, name: volume.title, rootURL: url)
        }
    }

    @concurrent func source(for url: URL) async throws -> OfflineCatalogSource {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { throw OfflineCatalogError.invalidSource }
        let rootURL = url.resolvingSymlinksInPath().standardizedFileURL
        let connected = try await volumes()
        let candidates = connected.filter { (try? OfflineCatalogValidation.relativePath(of: rootURL, in: $0.rootURL)) != nil }
            .sorted { $0.rootURL.pathComponents.count > $1.rootURL.pathComponents.count }
        guard let volume = candidates.first else { throw OfflineCatalogError.invalidSource }
        guard connected.count(where: { $0.id == volume.id }) == 1 else { throw OfflineCatalogError.ambiguousVolume }
        return try scopedSource(rootURL: rootURL, volume: volume)
    }

    @concurrent func source(for summary: OfflineCatalogSummary) async throws -> OfflineCatalogSource {
        try summary.validate()
        let matches = try await volumes().filter { $0.id == summary.volumeID }
        guard let volume = matches.first else { throw OfflineCatalogError.unavailableVolume }
        guard matches.count == 1 else { throw OfflineCatalogError.ambiguousVolume }
        let url = summary.relativeRoot.isEmpty ? volume.rootURL : volume.rootURL.appending(path: summary.relativeRoot)
        let source = try scopedSource(rootURL: url, volume: volume)
        guard source.rootInode == summary.rootInode else { throw OfflineCatalogError.changedItem }
        return source
    }

    @concurrent func reveal(_ entry: OfflineCatalogEntry, in summary: OfflineCatalogSummary) async throws -> URL {
        try OfflineCatalogValidation.path(entry.relativePath)
        let source = try await source(for: summary)
        let root = try ScopedFolderDescriptor(rootURL: source.rootURL)
        guard try root.state().inode == summary.rootInode else { throw OfflineCatalogError.changedItem }
        let components = try ScopedFolderDescriptor.components(entry.relativePath)
        let parent = try root.directory(Array(components.dropLast()))
        guard let name = components.last, let state = try parent.state(of: name),
              state.inode == entry.inode, state.isDirectory == entry.isDirectory,
              state.isRegularFile || state.isDirectory, state.isPlaceholder == false,
              try state.device == root.state().device else { throw OfflineCatalogError.changedItem }
        // No suspension between validating the current mount/entry and returning
        // its location. This only reveals the item; it never executes or modifies it.
        try Task.checkCancellation()
        return source.rootURL.appending(path: entry.relativePath)
    }

    private func scopedSource(rootURL: URL, volume: OfflineCatalogVolume) throws -> OfflineCatalogSource {
        try Task.checkCancellation()
        let relative = try OfflineCatalogValidation.relativePath(of: rootURL, in: volume.rootURL)
        let volumeRoot = try ScopedFolderDescriptor(rootURL: volume.rootURL)
        let root = try volumeRoot.directory(relative.isEmpty ? [] : ScopedFolderDescriptor.components(relative))
        let state = try root.state()
        guard rootURL.path != "/", state.isDirectory, state.isPlaceholder == false, state.inode > 0,
              try state.device == volumeRoot.state().device,
              (try rootURL.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else { throw OfflineCatalogError.invalidSource }
        return OfflineCatalogSource(volume: volume, relativeRoot: relative, rootInode: state.inode)
    }
}
