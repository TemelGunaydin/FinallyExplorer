import Darwin
import Foundation

nonisolated protocol VisualSearchScanning: Sendable {
    func scan(rootURL: URL, includesHidden: Bool,
              progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> VisualSearchSnapshot
    func validate(_ entry: VisualSearchSnapshot.Entry, in snapshot: VisualSearchSnapshot) async throws -> URL
}

nonisolated struct VisualSearchService: VisualSearchScanning {
    let analyzer: any VisualImageAnalyzing
    var imageLimit = 300
    var entryLimit = 25_000
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp"]

    init(analyzer: any VisualImageAnalyzing = VisionImageAnalyzer()) { self.analyzer = analyzer }

    @concurrent func scan(rootURL: URL, includesHidden: Bool,
                         progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }) async throws -> VisualSearchSnapshot {
        try Task.checkCancellation()
        guard rootURL.isFileURL, rootURL.host == nil || rootURL.host == "" || rootURL.host == "localhost" else {
            throw VisualSearchError.invalidFolder
        }
        let url = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .isPackageKey])
        guard url.path != "/", values.volumeIsLocal == true, values.isPackage != true else { throw VisualSearchError.invalidFolder }
        let root = try ScopedFolderDescriptor(rootURL: url)
        let state = try root.state()
        guard state.isPlaceholder == false else { throw VisualSearchError.invalidFolder }
        let (tree, excluded) = try await FolderTreeScanner.scan(root, rootURL: url, includesHidden: includesHidden,
            entryLimit: entryLimit, pathByteLimit: 2 * 1_024 * 1_024, progress: progress)
        let candidates = tree.values.filter {
            $0.skippedReason == nil && $0.state.isRegularFile && Self.extensions.contains(URL(filePath: $0.relativePath).pathExtension.lowercased())
        }.sorted { $0.relativePath < $1.relativePath }
        guard candidates.count <= imageLimit else { throw VisualSearchError.tooManyImages }
        var entries: [VisualSearchSnapshot.Entry] = []
        var skipped: [VisualSearchSnapshot.Skipped] = []
        for (index, entry) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress(FolderWorkProgress(phase: "Analyzing images on this Mac…", relativePath: entry.relativePath,
                completedItems: index, totalItems: candidates.count))
            if entry.state.size > 40 * 1_024 * 1_024 {
                skipped.append(.init(relativePath: entry.relativePath, reason: VisualSearchError.imageTooLarge.localizedDescription))
                continue
            }
            // Filesystem failures invalidate the scan; an unsupported image only skips that image.
            let data = try Self.read(entry, root: root)
            do {
                let evidence = try await analyzer.analyze(data)
                try Task.checkCancellation()
                entries.append(.init(relativePath: entry.relativePath, state: entry.state, evidence: evidence))
            } catch {
                try Task.checkCancellation()
                // A request/backend failure must not masquerade as a successful empty index.
                guard let imageError = error as? VisualSearchError,
                      imageError == .imageTooLarge || imageError == .unreadableImage else { throw VisualSearchError.unavailable }
                skipped.append(.init(relativePath: entry.relativePath, reason: imageError.localizedDescription))
            }
        }
        await progress(FolderWorkProgress(phase: "Checking image snapshot…", relativePath: url.path,
            completedItems: candidates.count, totalItems: candidates.count))
        try FolderTreeScanner.validate(root, root: state, entries: tree)
        guard try ScopedFolderDescriptor(rootURL: url).state() == state else { throw VisualSearchError.changed }
        try Task.checkCancellation()
        return VisualSearchSnapshot(rootURL: url, rootState: state, tree: tree, entries: entries, skipped: skipped,
            excludedHiddenCount: excluded, excludedOtherCount: tree.values.filter { $0.skippedReason != nil }.count, scannedAt: .now)
    }

    @concurrent func validate(_ entry: VisualSearchSnapshot.Entry, in snapshot: VisualSearchSnapshot) async throws -> URL {
        try Task.checkCancellation()
        guard snapshot.entries.contains(where: { $0.id == entry.id && $0.state == entry.state }) else { throw VisualSearchError.changed }
        let root = try ScopedFolderDescriptor(rootURL: snapshot.rootURL)
        guard try root.state().hasSameIdentity(as: snapshot.rootState) else { throw VisualSearchError.changed }
        let components = try ScopedFolderDescriptor.components(entry.relativePath)
        for count in 1..<components.count {
            let path = components.prefix(count).joined(separator: "/")
            guard let expected = snapshot.tree[path]?.state,
                  try root.directory(Array(components.prefix(count))).state().hasSameIdentity(as: expected) else { throw VisualSearchError.changed }
        }
        let parent = try root.directory(Array(components.dropLast()))
        let file = try parent.openFile(components[components.count - 1])
        guard try file.state() == entry.state else { throw VisualSearchError.changed }
        try Task.checkCancellation()
        return snapshot.rootURL.appending(path: entry.relativePath)
    }

    private static func read(_ entry: ComparedFolderEntry, root: ScopedFolderDescriptor) throws -> Data {
        let components = try ScopedFolderDescriptor.components(entry.relativePath)
        let parent = try root.directory(Array(components.dropLast()))
        let file = try parent.openFile(components[components.count - 1])
        guard try file.state() == entry.state, entry.state.size >= 0 else { throw VisualSearchError.changed }
        var data = Data()
        data.reserveCapacity(Int(entry.state.size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file.rawValue, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw FolderComparisonError.fileSystem(entry.relativePath, errno)
            }
            if count == 0 { break }
            guard data.count + count <= entry.state.size else { throw VisualSearchError.changed }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == entry.state.size, try file.state() == entry.state else { throw VisualSearchError.changed }
        return data
    }
}
