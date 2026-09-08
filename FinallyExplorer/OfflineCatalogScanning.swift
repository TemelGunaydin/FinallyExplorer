import Foundation

nonisolated protocol OfflineCatalogScanning: Sendable {
    func scan(_ source: OfflineCatalogSource, includesHidden: Bool,
              progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> OfflineCatalogSnapshot
}
