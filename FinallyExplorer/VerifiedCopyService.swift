import Darwin
import Foundation

nonisolated protocol VerifiedCopyServicing: Sendable {
    func copy(_ plan: VerifiedCopyPlan, progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async -> VerifiedCopyReport
}

nonisolated struct VerifiedCopyService: VerifiedCopyServicing {
    @concurrent
    func copy(
        _ plan: VerifiedCopyPlan,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async -> VerifiedCopyReport {
        var report = VerifiedCopyReport(destinationURL: plan.snapshot.destinationURL)
        do {
            try Task.checkCancellation()
            let snapshot = plan.snapshot
            try FolderComparisonService.validateRoots(snapshot.sourceURL, snapshot.destinationURL)
            let source = try ScopedFolderDescriptor(rootURL: snapshot.sourceURL)
            let destination = try ScopedFolderDescriptor(rootURL: snapshot.destinationURL)
            guard try source.state().hasSameIdentity(as: snapshot.sourceRoot),
                  try destination.state().hasSameIdentity(as: snapshot.destinationRoot) else {
                throw FolderComparisonError.changed("The selected folders")
            }
            guard try source.containsDirectory(destination) == false,
                  try destination.containsDirectory(source) == false else { throw FolderComparisonError.overlappingFolders }
            // Check the entire approved plan before creating anything.
            for entry in plan.entries {
                try Task.checkCancellation()
                let names = try ScopedFolderDescriptor.components(entry.relativePath)
                let parentNames = Array(names.dropLast())
                let sourceParent = try checkedDirectory(source, components: parentNames, expected: snapshot.sourceEntries)
                guard try sourceParent.state(of: names[names.count - 1]) == entry.state else {
                    throw FolderComparisonError.changed(entry.relativePath)
                }
                try checkDestination(destination, names: names, expected: snapshot.destinationEntries)
            }

            var destinationEntries = snapshot.destinationEntries
            var copiedBytes: Int64 = 0
            for (index, entry) in plan.entries.enumerated() {
                try Task.checkCancellation()
                try validateRootLocations(snapshot)
                let names = try ScopedFolderDescriptor.components(entry.relativePath)
                let parentNames = Array(names.dropLast()), name = names[names.count - 1]
                let sourceParent = try checkedDirectory(source, components: parentNames, expected: snapshot.sourceEntries)
                let destinationParent = try checkedDirectory(destination, components: parentNames, expected: destinationEntries)
                guard try sourceParent.state(of: name) == entry.state else { throw FolderComparisonError.changed(entry.relativePath) }
                guard try destinationParent.state(of: name) == nil else { throw FolderComparisonError.collision(entry.relativePath) }
                if entry.state.isDirectory {
                    guard mkdirat(destinationParent.rawValue, name, 0o755) == 0 else {
                        throw FolderComparisonError.fileSystem(entry.relativePath, errno)
                    }
                    // Record successful writes immediately, even if later work is cancelled.
                    report.createdDirectories.append(entry.relativePath)
                    let newDirectory = try destinationParent.directory([name])
                    destinationEntries[entry.relativePath] = ComparedFolderEntry(
                        relativePath: entry.relativePath, state: try newDirectory.state(), sha256: nil, skippedReason: nil
                    )
                } else {
                    let priorBytes = copiedBytes
                    try await copyFile(entry, name: name, sourceParent: sourceParent, destinationParent: destinationParent, validateParents: {
                        try validateRootLocations(snapshot)
                        let currentSourceParent = try checkedDirectory(source, components: parentNames, expected: snapshot.sourceEntries)
                        let currentDestinationParent = try checkedDirectory(destination, components: parentNames, expected: destinationEntries)
                        guard try currentSourceParent.state().hasSameIdentity(as: sourceParent.state()),
                              try currentDestinationParent.state().hasSameIdentity(as: destinationParent.state()) else {
                            throw FolderComparisonError.changed(entry.relativePath)
                        }
                    }) { phase, bytes in
                        await progress(FolderWorkProgress(
                            phase: phase, relativePath: entry.relativePath, completedItems: index, totalItems: plan.entries.count,
                            completedBytes: priorBytes + bytes, totalBytes: plan.byteCount
                        ))
                    }
                    report.verifiedFiles.append(entry.relativePath)
                    copiedBytes += entry.state.size
                }
            }
        } catch is CancellationError {
            report.wasCancelled = true
        } catch {
            report.wasCancelled = Task.isCancelled
            report.errorMessage = error.localizedDescription
        }
        return report
    }

    private func copyFile(
        _ entry: ComparedFolderEntry, name: String,
        sourceParent: ScopedFolderDescriptor, destinationParent: ScopedFolderDescriptor,
        validateParents: () throws -> Void,
        progress: @escaping @Sendable (String, Int64) async -> Void
    ) async throws {
        let source = try sourceParent.openFile(name)
        guard try source.state() == entry.state, let expectedHash = entry.sha256 else {
            throw FolderComparisonError.changed(entry.relativePath)
        }
        let stagingName = ".finally-verified-\(UUID().uuidString)"
        let staging = try ScopedFolderDescriptor(
            taking: openat(destinationParent.rawValue, stagingName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600),
            path: entry.relativePath
        )
        let stagingIdentity = try staging.state()
        do {
            await progress("Copying to a temporary file…", 0)
            let copiedHash = try await ComparedFileHasher.digest(source, expected: entry.state, path: entry.relativePath, copyingTo: staging) {
                await progress("Copying to a temporary file…", $0)
            }
            guard copiedHash == expectedHash else { throw FolderComparisonError.changed(entry.relativePath) }
            // Apple metadata copy preserves resource forks, xattrs and permissions;
            // the integrity claim below is explicitly limited to regular file data.
            guard fcopyfile(source.rawValue, staging.rawValue, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
                throw FolderComparisonError.fileSystem(entry.relativePath, errno)
            }
            guard fsync(staging.rawValue) == 0 else { throw FolderComparisonError.fileSystem(entry.relativePath, errno) }
            await progress("Verifying copied data…", entry.state.size)
            let stagedState = try staging.state()
            let verifiedHash = try await ComparedFileHasher.digest(staging, expected: stagedState, path: entry.relativePath)
            guard verifiedHash == expectedHash else { throw FolderComparisonError.verificationFailed(entry.relativePath) }
            try Task.checkCancellation()
            try validateParents()
            guard try source.state() == entry.state, try sourceParent.state(of: name) == entry.state,
                  try staging.state() == stagedState,
                  try destinationParent.state(of: stagingName)?.hasSameIdentity(as: stagingIdentity) == true else {
                throw FolderComparisonError.changed(entry.relativePath)
            }
            guard renameatx_np(destinationParent.rawValue, stagingName, destinationParent.rawValue, name, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw FolderComparisonError.collision(entry.relativePath) }
                throw FolderComparisonError.fileSystem(entry.relativePath, errno)
            }
        } catch {
            let originalError = error
            do {
                if let current = try destinationParent.state(of: stagingName), current.hasSameIdentity(as: stagingIdentity) {
                    // Only our unpublished entry is removed, never a pre-existing file.
                    _ = fchflags(staging.rawValue, 0)
                    guard unlinkat(destinationParent.rawValue, stagingName, 0) == 0 else {
                        throw FolderComparisonError.fileSystem(stagingName, errno)
                    }
                }
            } catch {
                let parent = entry.relativePath.split(separator: "/").dropLast().joined(separator: "/")
                throw FolderComparisonError.stagingCleanupFailed(parent.isEmpty ? stagingName : parent + "/" + stagingName)
            }
            throw originalError
        }
    }

    private func validateRootLocations(_ snapshot: FolderComparisonSnapshot) throws {
        let source = try ScopedFolderDescriptor(rootURL: snapshot.sourceURL)
        let destination = try ScopedFolderDescriptor(rootURL: snapshot.destinationURL)
        guard try source.state().hasSameIdentity(as: snapshot.sourceRoot),
              try destination.state().hasSameIdentity(as: snapshot.destinationRoot) else {
            throw FolderComparisonError.changed("The selected folders")
        }
    }

    private func checkedDirectory(
        _ root: ScopedFolderDescriptor, components: [String], expected: [String: ComparedFolderEntry]
    ) throws -> ScopedFolderDescriptor {
        var folder = try root.directory([])
        var path = ""
        for component in components {
            path = path.isEmpty ? component : path + "/" + component
            guard let entry = expected[path], entry.state.isDirectory, entry.skippedReason == nil else {
                throw FolderComparisonError.changed(path)
            }
            folder = try folder.directory([component])
            guard try folder.state().hasSameIdentity(as: entry.state) else { throw FolderComparisonError.changed(path) }
        }
        return folder
    }

    private func checkDestination(_ root: ScopedFolderDescriptor, names: [String], expected: [String: ComparedFolderEntry]) throws {
        var folder = try root.directory([])
        var path = ""
        for (index, name) in names.enumerated() {
            path = path.isEmpty ? name : path + "/" + name
            guard let state = try folder.state(of: name) else { return }
            guard index < names.count - 1, let original = expected[path], original.state.isDirectory,
                  original.skippedReason == nil, state.hasSameIdentity(as: original.state) else {
                throw FolderComparisonError.collision(path)
            }
            folder = try folder.directory([name])
        }
    }
}
