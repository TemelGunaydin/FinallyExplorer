import Foundation

nonisolated protocol OfflineCatalogStoring: Sendable {
    func list() async throws -> [OfflineCatalogSummary]
    func load(_ id: UUID) async throws -> OfflineCatalogSnapshot
    func save(_ snapshot: OfflineCatalogSnapshot) async throws -> OfflineCatalogSummary
    func remove(_ id: UUID) async throws
}
