import Foundation

nonisolated struct DuplicateScanSnapshot: Sendable {
    let rootURL: URL
    let rootState: ComparedFileState
    let entries: [String: ComparedFolderEntry]
    let groups: [DuplicateGroup]
    let skipped: [ComparedFolderEntry]
    let excludedHiddenCount: Int
    let hashedFileCount: Int
    let duplicateBytes: Int64
}
