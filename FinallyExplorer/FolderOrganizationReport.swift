import Foundation

nonisolated struct FolderOrganizationReport: Sendable {
    let rootURL: URL
    var movedFiles: [FolderOrganizationMove] = []
    var createdFolders: [String] = []
    var wasCancelled = false
    var errorMessage: String?

    var changedDirectories: Set<URL> {
        guard movedFiles.isEmpty == false || createdFolders.isEmpty == false else { return [] }
        return Set([rootURL] + movedFiles.map { rootURL.appending(path: $0.destinationFolder) }
                   + createdFolders.map { rootURL.appending(path: $0) })
    }

    var summary: String {
        let state = wasCancelled ? "Stopped" : errorMessage == nil ? "Finished" : "Organization stopped"
        return "\(state) · Files moved: \(movedFiles.count) · Folders created: \(createdFolders.count)"
    }
}
