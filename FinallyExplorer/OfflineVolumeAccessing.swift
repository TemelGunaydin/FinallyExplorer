import Foundation

nonisolated protocol OfflineVolumeAccessing: Sendable {
    func volumes() async throws -> [OfflineCatalogVolume]
    func source(for url: URL) async throws -> OfflineCatalogSource
    func source(for summary: OfflineCatalogSummary) async throws -> OfflineCatalogSource
    func reveal(_ entry: OfflineCatalogEntry, in summary: OfflineCatalogSummary) async throws -> URL
}
