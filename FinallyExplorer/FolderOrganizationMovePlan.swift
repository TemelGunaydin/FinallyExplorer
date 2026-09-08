import Foundation

nonisolated struct FolderOrganizationMovePlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: FolderOrganizationPlan
    let moves: [FolderOrganizationMove]
    let foldersToCreate: [String]

    init(snapshot: FolderOrganizationPlan) throws {
        guard snapshot.rootURL.isFileURL, snapshot.rootURL.path != "/", snapshot.rootState.isDirectory,
              snapshot.proposed.isEmpty == false, snapshot.proposed.count <= 50_000 else {
            throw FolderOrganizationError.invalidPlan
        }
        var moves: [FolderOrganizationMove] = []
        var sources: Set<String> = [], targets: Set<String> = [], newFolders: Set<String> = []
        for row in snapshot.proposed {
            let names = try ScopedFolderDescriptor.components(row.sourcePath)
            let target = try ScopedFolderDescriptor.components(row.destinationPath ?? "")
            guard names.count == 1, target.count == 2, target[1] == names[0], target[0] != names[0],
                  row.skippedReason == nil, let entry = snapshot.entries[row.sourcePath], entry.skippedReason == nil,
                  entry.state.isRegularFile, entry.state.isPlaceholder == false, entry.state.linkCount == 1,
                  entry.state.device == snapshot.rootState.device,
                  sources.insert(row.sourcePath).inserted, targets.insert(target.joined(separator: "/")).inserted else {
                throw FolderOrganizationError.invalidPlan
            }
            if let folder = snapshot.destinationFolders[target[0]] {
                guard folder.isDirectory, folder.isPlaceholder == false,
                      folder.device == snapshot.rootState.device else { throw FolderOrganizationError.invalidPlan }
            } else { newFolders.insert(target[0]) }
            moves.append(FolderOrganizationMove(sourceName: names[0], destinationFolder: target[0], sourceState: entry.state))
        }
        self.snapshot = snapshot
        self.moves = moves.sorted { $0.sourceName < $1.sourceName }
        foldersToCreate = newFolders.sorted()
    }
}
