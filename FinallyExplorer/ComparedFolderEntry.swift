import Foundation

nonisolated struct ComparedFolderEntry: Sendable {
    let relativePath: String
    let state: ComparedFileState
    var sha256: Data?
    let skippedReason: String?
}
