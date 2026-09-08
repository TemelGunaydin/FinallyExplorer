import Foundation

/// Serializes local catalog commits across windows. Scans never write to a disk
/// being cataloged. A new payload is published only by an atomic manifest swap.
actor OfflineCatalogStore: OfflineCatalogStoring {
    static let shared = OfflineCatalogStore()
    private let rootURL: URL
    private var manifestURL: URL { rootURL.appending(path: "catalogs-v1.json") }

    init(rootURL: URL = URL.applicationSupportDirectory.appending(path: "FinallyExplorer/OfflineCatalogs")) {
        self.rootURL = rootURL
    }

    func list() throws -> [OfflineCatalogSummary] {
        try readManifest().records.map(\.summary).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func load(_ id: UUID) throws -> OfflineCatalogSnapshot {
        let manifest = try readManifest()
        guard let record = manifest.records.first(where: { $0.summary.id == id }) else { throw OfflineCatalogError.invalidCatalog }
        let data = try boundedData(at: payloadURL(record), limit: OfflineCatalogValidation.payloadByteLimit)
        let snapshot: OfflineCatalogSnapshot
        do { snapshot = try JSONDecoder().decode(OfflineCatalogSnapshot.self, from: data) }
        catch { throw OfflineCatalogError.invalidCatalog }
        try snapshot.validate()
        guard snapshot.summary == record.summary else { throw OfflineCatalogError.invalidCatalog }
        return snapshot
    }

    func save(_ snapshot: OfflineCatalogSnapshot) throws -> OfflineCatalogSummary {
        try snapshot.validate()
        var manifest = try readManifest()
        let incoming = snapshot.summary
        let old = manifest.records.first { $0.summary.volumeID == incoming.volumeID && $0.summary.relativeRoot == incoming.relativeRoot }
        guard old != nil || manifest.records.count < OfflineCatalogValidation.catalogLimit else { throw OfflineCatalogError.catalogLimit }
        let summary = OfflineCatalogSummary(id: old?.summary.id ?? UUID(), volumeID: incoming.volumeID, volumeName: incoming.volumeName,
            relativeRoot: incoming.relativeRoot, rootInode: incoming.rootInode, scannedAt: incoming.scannedAt,
            includesHidden: incoming.includesHidden, entryCount: incoming.entryCount, skippedCount: incoming.skippedCount,
            excludedHiddenCount: incoming.excludedHiddenCount)
        let record = OfflineCatalogRecord(summary: summary, generation: UUID())
        let data = try JSONEncoder().encode(OfflineCatalogSnapshot(summary: summary, entries: snapshot.entries))
        guard data.count <= OfflineCatalogValidation.payloadByteLimit else { throw OfflineCatalogError.tooLarge }
        try Task.checkCancellation()
        let directory = catalogDirectory(summary.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
        let newPayload = payloadURL(record)
        do {
            try data.write(to: newPayload, options: .atomic)
            try Task.checkCancellation()
            manifest.records.removeAll { $0.summary.id == summary.id }
            manifest.records.append(record)
            try publish(manifest)
        } catch {
            try? FileManager.default.removeItem(at: newPayload)
            throw error
        }
        // No throwing cancellation check after publication: this snapshot is saved.
        if let old { try? FileManager.default.removeItem(at: payloadURL(old)) }
        return summary
    }

    func remove(_ id: UUID) throws {
        var manifest = try readManifest()
        guard manifest.records.contains(where: { $0.summary.id == id }) else { return }
        try Task.checkCancellation()
        manifest.records.removeAll { $0.summary.id == id }
        try publish(manifest)
        do { try FileManager.default.removeItem(at: catalogDirectory(id)) }
        catch {
            if let error = error as? CocoaError, error.code == .fileNoSuchFile { return }
            throw OfflineCatalogError.cleanupFailed
        }
    }

    private func readManifest() throws -> OfflineCatalogManifest {
        try Task.checkCancellation()
        do { _ = try FileManager.default.attributesOfItem(atPath: manifestURL.path) }
        catch {
            if let error = error as? CocoaError, error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return OfflineCatalogManifest()
            }
            throw error
        }
        let data = try boundedData(at: manifestURL, limit: 1_000_000)
        let manifest: OfflineCatalogManifest
        do { manifest = try JSONDecoder().decode(OfflineCatalogManifest.self, from: data) }
        catch { throw OfflineCatalogError.invalidCatalog }
        guard manifest.version == 1, manifest.records.count <= OfflineCatalogValidation.catalogLimit,
              Set(manifest.records.map { $0.summary.id }).count == manifest.records.count else { throw OfflineCatalogError.invalidCatalog }
        var scopes: [UUID: Set<String>] = [:]
        for record in manifest.records {
            try record.summary.validate()
            guard scopes[record.summary.volumeID, default: []].insert(record.summary.relativeRoot).inserted else {
                throw OfflineCatalogError.invalidCatalog
            }
        }
        return manifest
    }

    private func boundedData(at url: URL, limit: Int) throws -> Data {
        let folder = try ScopedFolderDescriptor(rootURL: url.deletingLastPathComponent())
        let file = try folder.openFile(url.lastPathComponent)
        let state = try file.state()
        guard state.size >= 0, state.size <= limit else { throw OfflineCatalogError.invalidCatalog }
        // Use the already validated no-follow descriptor, not a second path open.
        let handle = FileHandle(fileDescriptor: file.rawValue, closeOnDealloc: false)
        guard let data = try handle.read(upToCount: limit + 1), data.count <= limit, data.count == state.size else { throw OfflineCatalogError.invalidCatalog }
        try Task.checkCancellation()
        guard try file.state() == state else { throw OfflineCatalogError.invalidCatalog }
        return data
    }

    private func publish(_ manifest: OfflineCatalogManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try Task.checkCancellation()
        try data.write(to: manifestURL, options: .atomic)
    }

    private func catalogDirectory(_ id: UUID) -> URL { rootURL.appending(path: id.uuidString, directoryHint: .isDirectory) }
    private func payloadURL(_ record: OfflineCatalogRecord) -> URL {
        catalogDirectory(record.summary.id).appending(path: record.generation.uuidString + ".json")
    }
}
