import Foundation
@testable import FinallyExplorer

nonisolated struct OfflineCatalogTestFixture: Sendable {
    let files: FolderComparisonTestFixture
    let volume: OfflineCatalogVolume
    let store: OfflineCatalogStore
    let storageURL: URL
    var access: LocalOfflineVolumeAccess { LocalOfflineVolumeAccess(fixtureVolumes: [volume]) }

    init() throws {
        files = try FolderComparisonTestFixture()
        volume = OfflineCatalogVolume(id: UUID(), name: "Archive Disk", rootURL: files.source)
        storageURL = files.destination.appending(path: "Catalogs")
        store = OfflineCatalogStore(rootURL: storageURL)
    }

    func remove() { files.remove() }
    func scan(includesHidden: Bool = false) async throws -> OfflineCatalogSnapshot {
        try await OfflineCatalogScanner(volumes: access).scan(access.source(for: files.source), includesHidden: includesHidden, progress: { _ in })
    }
}
