import Foundation

nonisolated struct OfflineCatalogEntry: Codable, Identifiable, Equatable, Sendable {
    let relativePath: String
    let isDirectory: Bool
    let byteCount: Int64?
    let modifiedAt: Date
    let inode: UInt64

    var id: String { relativePath }
    var name: String { relativePath.split(separator: "/").last.map(String.init) ?? relativePath }
}
