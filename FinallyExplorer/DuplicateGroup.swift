import Foundation

nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let files: [ComparedFolderEntry]
    let fileSize: Int64

    var duplicateBytes: Int64 { fileSize * Int64(max(files.count - 1, 0)) }
}
