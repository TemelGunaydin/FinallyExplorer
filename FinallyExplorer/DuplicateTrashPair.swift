import Foundation

nonisolated struct DuplicateTrashPair: Identifiable, Sendable {
    let remove: ComparedFolderEntry
    let keep: ComparedFolderEntry
    var id: String { remove.relativePath }
}
