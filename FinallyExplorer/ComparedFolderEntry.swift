import Foundation

nonisolated struct ComparedFolderEntry: Sendable {
    let relativePath: String
    let state: ComparedFileState
    var sha256: Data?
    var skippedReason: String?
}
