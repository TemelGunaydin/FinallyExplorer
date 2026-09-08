import Foundation

nonisolated struct DuplicateTrashReport: Sendable {
    let rootURL: URL
    var trashedPaths: [String] = []
    var wasCancelled = false
    var errorMessage: String?

    var changedDirectories: Set<URL> {
        Set(trashedPaths.map { rootURL.appending(path: $0).deletingLastPathComponent() })
    }
    var summary: String {
        let state = wasCancelled ? "Stopped" : errorMessage == nil ? "Finished" : "Operation stopped"
        return "\(state) · Files moved to Trash: \(trashedPaths.count)"
    }
}
