import Foundation

nonisolated struct OfflineCatalogManifest: Codable, Sendable {
    var version = 1
    var records: [OfflineCatalogRecord] = []
}
