import Foundation

nonisolated protocol DuplicateTrashing: Sendable {
    func trash(_ plan: DuplicateTrashPlan, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async -> DuplicateTrashReport
}

nonisolated struct DuplicateTrashService: DuplicateTrashing {
    let fileOperations: any FileOperationServicing

    init(fileOperations: any FileOperationServicing = FileOperationService()) { self.fileOperations = fileOperations }

    @concurrent
    func trash(
        _ plan: DuplicateTrashPlan,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async -> DuplicateTrashReport {
        var report = DuplicateTrashReport(rootURL: plan.snapshot.rootURL)
        do {
            // Validate the full reviewed plan before the first destructive operation.
            for (index, pair) in plan.pairs.enumerated() {
                await progress(FolderWorkProgress(phase: "Rechecking selected files and retained copies…", relativePath: pair.id,
                    completedItems: index, totalItems: plan.pairs.count))
                try await validate(pair, snapshot: plan.snapshot)
            }
            for (index, pair) in plan.pairs.enumerated() {
                try Task.checkCancellation()
                await progress(FolderWorkProgress(phase: "Moving approved duplicates to Trash…", relativePath: pair.id,
                    completedItems: index, totalItems: plan.pairs.count))
                // Revalidate at each mutation boundary, including the copy being kept.
                try await validate(pair, snapshot: plan.snapshot)
                try Task.checkCancellation()
                let outcome = try await fileOperations.trashItem(at: plan.snapshot.rootURL.appending(path: pair.id))
                if outcome.didChange { report.trashedPaths.append(pair.id) }
            }
            report.wasCancelled = Task.isCancelled
        } catch is CancellationError {
            report.wasCancelled = true
        } catch {
            report.wasCancelled = Task.isCancelled
            report.errorMessage = FileToolsError.message(for: error)
        }
        return report
    }

    private func validate(_ pair: DuplicateTrashPair, snapshot: DuplicateScanSnapshot) async throws {
        try Task.checkCancellation()
        let root = try ScopedFolderDescriptor(rootURL: snapshot.rootURL)
        guard try root.state().hasSameIdentity(as: snapshot.rootState) else { throw FileToolsError.scanAgain(snapshot.rootURL.path) }
        for entry in [pair.remove, pair.keep] {
            let file = try DuplicateFileVerifier.open(entry, root: root)
            let hash = try await ComparedFileHasher.digest(file, expected: entry.state, path: entry.relativePath)
            guard hash == entry.sha256 else { throw FileToolsError.scanAgain(entry.relativePath) }
        }
        guard try DuplicateFileVerifier.equalData(pair.remove, pair.keep, root: root) else { throw FileToolsError.scanAgain(pair.id) }
        let current = try ScopedFolderDescriptor(rootURL: snapshot.rootURL)
        guard try current.state().hasSameIdentity(as: snapshot.rootState) else { throw FileToolsError.scanAgain(snapshot.rootURL.path) }
        // Ensure names still resolve to the validated entries after the reads.
        _ = try DuplicateFileVerifier.open(pair.remove, root: current)
        _ = try DuplicateFileVerifier.open(pair.keep, root: current)
    }
}
