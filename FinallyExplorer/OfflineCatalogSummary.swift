import Foundation

nonisolated struct OfflineCatalogSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let volumeID: UUID
    let volumeName: String
    let relativeRoot: String
    let rootInode: UInt64
    let scannedAt: Date
    let includesHidden: Bool
    let entryCount: Int
    let skippedCount: Int
    let excludedHiddenCount: Int

    var title: String { relativeRoot.isEmpty ? volumeName : "\(volumeName) · \(relativeRoot)" }

    func validate() throws {
        try OfflineCatalogValidation.path(relativeRoot, allowsEmpty: true)
        guard volumeName.isEmpty == false, volumeName.utf8.count <= 1_024,
              rootInode > 0, scannedAt.timeIntervalSince1970.isFinite,
              (0...OfflineCatalogValidation.entryLimit).contains(entryCount), skippedCount >= 0, excludedHiddenCount >= 0 else {
            throw OfflineCatalogError.invalidCatalog
        }
    }
}
