import Foundation

nonisolated struct FolderComparisonLocation: Identifiable, Sendable {
    let id: UUID
    let title: String
    let url: URL
}
