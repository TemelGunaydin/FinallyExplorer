import Darwin
import Foundation

nonisolated protocol FolderOrganizationApplying: Sendable {
    func apply(_ plan: FolderOrganizationMovePlan,
               progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async -> FolderOrganizationReport
}

nonisolated struct FolderOrganizationApplyService: FolderOrganizationApplying {
    @concurrent
    func apply(
        _ plan: FolderOrganizationMovePlan,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async -> FolderOrganizationReport {
        var report = FolderOrganizationReport(rootURL: plan.snapshot.rootURL)
        do {
            try Task.checkCancellation()
            let root = try checkedRoot(plan.snapshot)
            // No writes until every approved source and destination passes preflight.
            for (index, move) in plan.moves.enumerated() {
                if index.isMultiple(of: 100) {
                    await progress(FolderWorkProgress(phase: "Checking approved moves…", relativePath: move.sourceName,
                        completedItems: index, totalItems: plan.moves.count))
                }
                try Task.checkCancellation()
                try validateSource(move, root: root)
                try preflightDestination(move, root: root, snapshot: plan.snapshot)
            }
            var created: [String: ComparedFileState] = [:]
            for (index, move) in plan.moves.enumerated() {
                await progress(FolderWorkProgress(phase: "Moving approved files…", relativePath: move.sourceName,
                    completedItems: index, totalItems: plan.moves.count))
                try Task.checkCancellation()
                _ = try checkedRoot(plan.snapshot)
                try validateSource(move, root: root)
                let expected = created[move.destinationFolder] ?? plan.snapshot.destinationFolders[move.destinationFolder]
                if expected == nil {
                    guard try root.state(of: move.destinationFolder) == nil else {
                        throw FolderOrganizationError.collision(move.destinationFolder)
                    }
                    guard mkdirat(root.rawValue, move.destinationFolder, 0o755) == 0 else {
                        throw FolderOrganizationError.fileSystem(move.destinationFolder, errno)
                    }
                    // Record committed writes before any later cancellation or error.
                    report.createdFolders.append(move.destinationFolder)
                    created[move.destinationFolder] = try root.directory([move.destinationFolder]).state()
                }
                let folderState = created[move.destinationFolder] ?? expected
                let destination = try checkedDestination(move, root: root, expected: folderState)
                _ = try checkedRoot(plan.snapshot)
                try validateSource(move, root: root)
                try Task.checkCancellation()
                // Recheck the opened folder's binding immediately before the rename.
                // This narrows the external-change window; it is not a filesystem lock.
                guard let currentFolder = try root.state(of: move.destinationFolder),
                      currentFolder.device == plan.snapshot.rootState.device, currentFolder.isPlaceholder == false,
                      try destination.state().hasSameIdentity(as: currentFolder) else {
                    throw FolderOrganizationError.changed(move.destinationFolder)
                }
                // Exclusive same-volume rename preserves the file (including metadata),
                // and atomically refuses an existing name. Never fall back to copy/delete.
                guard renameatx_np(root.rawValue, move.sourceName, destination.rawValue, move.sourceName, UInt32(RENAME_EXCL)) == 0 else {
                    if errno == EEXIST { throw FolderOrganizationError.collision(move.destinationPath) }
                    throw FolderOrganizationError.fileSystem(move.destinationPath, errno)
                }
                report.movedFiles.append(move)
            }
            report.wasCancelled = Task.isCancelled
        } catch is CancellationError {
            report.wasCancelled = true
        } catch {
            report.wasCancelled = Task.isCancelled
            report.errorMessage = FolderOrganizationError.message(for: error)
        }
        return report
    }

    private func checkedRoot(_ snapshot: FolderOrganizationPlan) throws -> ScopedFolderDescriptor {
        let root = try ScopedFolderDescriptor(rootURL: snapshot.rootURL)
        guard try root.state().hasSameIdentity(as: snapshot.rootState) else {
            throw FolderOrganizationError.changed(snapshot.rootURL.path)
        }
        return root
    }

    private func validateSource(_ move: FolderOrganizationMove, root: ScopedFolderDescriptor) throws {
        let file = try root.openFile(move.sourceName)
        guard try file.state() == move.sourceState, try root.state(of: move.sourceName) == move.sourceState else {
            throw FolderOrganizationError.changed(move.sourceName)
        }
    }

    private func preflightDestination(_ move: FolderOrganizationMove, root: ScopedFolderDescriptor, snapshot: FolderOrganizationPlan) throws {
        if let original = snapshot.destinationFolders[move.destinationFolder] {
            _ = try checkedDestination(move, root: root, expected: original)
        } else if try root.state(of: move.destinationFolder) != nil {
            throw FolderOrganizationError.collision(move.destinationFolder)
        }
    }

    private func checkedDestination(_ move: FolderOrganizationMove, root: ScopedFolderDescriptor, expected: ComparedFileState?) throws -> ScopedFolderDescriptor {
        guard let expected, let current = try root.state(of: move.destinationFolder),
              current.hasSameIdentity(as: expected), current.isPlaceholder == false else {
            throw FolderOrganizationError.changed(move.destinationFolder)
        }
        let folder = try root.directory([move.destinationFolder])
        guard try folder.state().hasSameIdentity(as: expected) else { throw FolderOrganizationError.changed(move.destinationFolder) }
        guard try folder.state(of: move.sourceName) == nil else { throw FolderOrganizationError.collision(move.destinationPath) }
        return folder
    }
}
