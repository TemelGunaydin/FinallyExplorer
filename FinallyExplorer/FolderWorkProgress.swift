import Foundation

nonisolated struct FolderWorkProgress: Sendable {
    let phase: String
    let relativePath: String
    var completedItems = 0
    var totalItems = 0
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0

    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}
