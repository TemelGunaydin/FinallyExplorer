import Foundation

nonisolated struct OfflineCatalogQuery: Sendable {
    var text = ""
    var fileExtension = ""
    var minimumBytes: Int64 = 0
    var modifiedSince: Date?
}
