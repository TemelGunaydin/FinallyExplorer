import Foundation

nonisolated struct OfflineCatalogRecord: Codable, Sendable {
    let summary: OfflineCatalogSummary
    let generation: UUID
}
