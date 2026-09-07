import Foundation

nonisolated struct FolderComparisonRow: Identifiable, Sendable {
    enum Status: String, CaseIterable, Sendable {
        case onlySource = "Only in Source"
        case onlyDestination = "Only in Destination"
        case same = "Same Data"
        case different = "Different Data"
        case folder = "Folder"
        case conflict = "Type Conflict"
        case skipped = "Not Compared"
    }

    let relativePath: String
    let source: ComparedFolderEntry?
    let destination: ComparedFolderEntry?
    let status: Status
    var id: String { relativePath }
}
