//
//  FileOperationServiceTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FinallyExplorer

struct FileOperationServiceTests {
    @Test("A file is copied into an empty destination")
    func copiesFile() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "note.txt")
        let sourceData = Data("Finally Explorer".utf8)
        try sourceData.write(to: sourceURL)

        let outcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.didChange)
        #expect(outcome.destinationURL == destinationDirectory.appending(path: "note.txt"))
        #expect(try Data(contentsOf: outcome.destinationURL) == sourceData)
        #expect(try Data(contentsOf: sourceURL) == sourceData)
    }

    @Test("A folder can be hidden, repeated safely, and unhidden")
    func folderVisibilityRoundTrips() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let folderURL = try makeDirectory(named: "Private", in: root)
        let service = FileOperationService()

        let hiddenOutcome = try await service.setHidden(true, for: folderURL)
        let hiddenValues = try folderURL.resourceValues(forKeys: [.isHiddenKey])
        let hiddenListing = try await FileSystemService().contents(
            of: root,
            folderTitle: "Fixture"
        )
        let completeListing = try await FileSystemService().contents(
            of: root,
            folderTitle: "Fixture",
            includingHiddenItems: true
        )

        #expect(hiddenOutcome.didChange)
        #expect(hiddenValues.isHidden == true)
        #expect(hiddenListing.isEmpty)
        #expect(completeListing.map(\.name) == ["Private"])
        #expect(completeListing.first?.isHidden == true)

        let repeatedOutcome = try await service.setHidden(true, for: folderURL)
        #expect(repeatedOutcome.didChange == false)

        let visibleOutcome = try await service.setHidden(false, for: folderURL)
        let refreshedFolderURL = URL(
            filePath: folderURL.path(),
            directoryHint: .isDirectory
        )
        let visibleValues = try refreshedFolderURL.resourceValues(
            forKeys: [.isHiddenKey]
        )
        #expect(visibleOutcome.didChange)
        #expect(visibleValues.isHidden == false)
    }

    @Test("Folder visibility rejects regular files")
    func folderVisibilityRejectsFiles() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appending(path: "note.txt")
        try Data().write(to: fileURL)

        await #expect(
            throws: FileOperationError.sourceIsNotDirectory(path: fileURL.path)
        ) {
            try await FileOperationService().setHidden(true, for: fileURL)
        }
    }

    @Test("A dot-prefixed folder cannot claim to be unhidden")
    func dotPrefixedFolderCannotBeUnhidden() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let folderURL = try makeDirectory(named: ".private", in: root)

        await #expect(
            throws: FileOperationError.cannotUnhideDotPrefixedDirectory(
                path: folderURL.path
            )
        ) {
            try await FileOperationService().setHidden(false, for: folderURL)
        }
    }

    @Test("Copy collisions use copy and copy 2 without overwriting existing files")
    func copyUsesUniqueFileNames() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "report.txt")
        let originalDestinationURL = destinationDirectory.appending(path: "report.txt")
        let firstCopyURL = destinationDirectory.appending(path: "report copy.txt")
        try Data("new".utf8).write(to: sourceURL)
        try Data("original".utf8).write(to: originalDestinationURL)
        try Data("first copy".utf8).write(to: firstCopyURL)

        let outcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.destinationURL.lastPathComponent == "report copy 2.txt")
        #expect(try readUTF8(outcome.destinationURL) == "new")
        #expect(try readUTF8(originalDestinationURL) == "original")
        #expect(try readUTF8(firstCopyURL) == "first copy")
    }

    @Test("Folders are copied recursively with unique folder names")
    func copiesFolderRecursively() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeDirectory(named: "Projects", in: root)
        let childURL = try makeDirectory(named: "Nested", in: sourceURL)
        try Data("content".utf8).write(to: childURL.appending(path: "item.txt"))

        let firstOutcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: root
        )
        let secondOutcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: root
        )

        #expect(firstOutcome.destinationURL.lastPathComponent == "Projects copy")
        #expect(secondOutcome.destinationURL.lastPathComponent == "Projects copy 2")
        #expect(
            try readUTF8(
                firstOutcome.destinationURL.appending(path: "Nested/item.txt")
            ) == "content"
        )
        #expect(
            try readUTF8(
                secondOutcome.destinationURL.appending(path: "Nested/item.txt")
            ) == "content"
        )
    }

    @Test("A file is moved into an empty destination")
    func movesFile() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "move-me.txt")
        try Data("moved".utf8).write(to: sourceURL)

        let outcome = try await FileOperationService().moveItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.didChange)
        #expect(outcome.destinationURL == destinationDirectory.appending(path: "move-me.txt"))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(try readUTF8(outcome.destinationURL) == "moved")
    }

    @Test("A folder is moved with its descendants")
    func movesFolderRecursively() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceParent = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = try makeDirectory(named: "Archive", in: sourceParent)
        let nestedURL = try makeDirectory(named: "Nested", in: sourceURL)
        try Data("kept".utf8).write(to: nestedURL.appending(path: "item.txt"))

        let outcome = try await FileOperationService().moveItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.didChange)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(
            try readUTF8(
                outcome.destinationURL.appending(path: "Nested/item.txt")
            ) == "kept"
        )
    }

    @Test("Moving to the current parent is a no-op")
    func sameParentMoveDoesNothing() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "already-here.txt")
        try Data("untouched".utf8).write(to: sourceURL)

        let outcome = try await FileOperationService().moveItem(at: sourceURL, to: root)

        #expect(outcome == FileOperationOutcome(destinationURL: sourceURL, didChange: false))
        #expect(try readUTF8(sourceURL) == "untouched")
    }

    @Test("A move collision fails without changing either item")
    func moveNeverOverwrites() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "same.txt")
        let destinationURL = destinationDirectory.appending(path: "same.txt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("destination".utf8).write(to: destinationURL)

        do {
            _ = try await FileOperationService().moveItem(
                at: sourceURL,
                to: destinationDirectory
            )
            Issue.record("Expected a destination collision error.")
        } catch let error as FileOperationError {
            #expect(error == .destinationAlreadyExists(path: destinationURL.path))
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(try readUTF8(sourceURL) == "source")
        #expect(try readUTF8(destinationURL) == "destination")
    }

    @Test("Copying a directory into itself is rejected")
    func copyRejectsDirectoryInsideItself() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeDirectory(named: "Folder", in: root)

        do {
            _ = try await FileOperationService().copyItem(at: sourceURL, to: sourceURL)
            Issue.record("Expected a recursive destination error.")
        } catch let error as FileOperationError {
            #expect(
                error == .cannotPlaceDirectoryInsideItself(
                    sourcePath: sourceURL.path,
                    destinationPath: sourceURL.path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("Moving a directory into a descendant is rejected")
    func moveRejectsDirectoryInsideDescendant() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeDirectory(named: "Folder", in: root)
        let childURL = try makeDirectory(named: "Child", in: sourceURL)

        do {
            _ = try await FileOperationService().moveItem(at: sourceURL, to: childURL)
            Issue.record("Expected a recursive destination error.")
        } catch let error as FileOperationError {
            #expect(
                error == .cannotPlaceDirectoryInsideItself(
                    sourcePath: sourceURL.path,
                    destinationPath: childURL.path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: childURL.path))
    }

    @Test("A missing source is reported before an operation starts")
    func rejectsMissingSource() async {
        let root: URL

        do {
            root = try makeFileOperationTemporaryDirectory()
        } catch {
            Issue.record("Unable to create the test fixture: \(error).")
            return
        }

        defer { try? FileManager.default.removeItem(at: root) }
        let missingURL = root.appending(path: "missing.txt")

        do {
            _ = try await FileOperationService().copyItem(at: missingURL, to: root)
            Issue.record("Expected a missing source error.")
        } catch let error as FileOperationError {
            #expect(error == .sourceNotFound(path: missingURL.path))
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("A missing destination is reported before an operation starts")
    func rejectsMissingDestination() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "source.txt")
        let missingDestinationURL = root.appending(
            path: "missing-destination",
            directoryHint: .isDirectory
        )
        try Data().write(to: sourceURL)

        do {
            _ = try await FileOperationService().copyItem(
                at: sourceURL,
                to: missingDestinationURL
            )
            Issue.record("Expected a missing destination error.")
        } catch let error as FileOperationError {
            #expect(
                error == .destinationNotFound(
                    path: missingDestinationURL.standardizedFileURL.path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("A destination file is rejected because it is not a folder")
    func rejectsDestinationFile() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appending(path: "source.txt")
        let destinationURL = root.appending(path: "not-a-folder.txt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("destination".utf8).write(to: destinationURL)

        do {
            _ = try await FileOperationService().moveItem(at: sourceURL, to: destinationURL)
            Issue.record("Expected a destination type error.")
        } catch let error as FileOperationError {
            #expect(error == .destinationIsNotDirectory(path: destinationURL.path))
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("A file URL with a remote host cannot be interpreted as a local source")
    func rejectsNonLocalFileSource() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let localSource = root.appending(path: "source.txt")
        try Data("unchanged".utf8).write(to: localSource)
        let remoteSource = try #require(
            URL(string: "file://example.com\(localSource.path(percentEncoded: true))")
        )

        do {
            _ = try await FileOperationService().copyItem(
                at: remoteSource,
                to: root
            )
            Issue.record("Expected a non-local source URL error.")
        } catch let error as FileOperationError {
            #expect(
                error == .sourceMustBeFileURL(value: remoteSource.absoluteString)
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(try readUTF8(localSource) == "unchanged")
    }

    @Test("A dangling symbolic link can be copied without following its target")
    func copiesDanglingSymbolicLink() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "shortcut")
        let occupiedURL = destinationDirectory.appending(path: "shortcut")
        try FileManager.default.createSymbolicLink(
            atPath: sourceURL.path,
            withDestinationPath: "missing-source-target"
        )
        try FileManager.default.createSymbolicLink(
            atPath: occupiedURL.path,
            withDestinationPath: "missing-destination-target"
        )

        let outcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.destinationURL.lastPathComponent == "shortcut copy")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: outcome.destinationURL.path
            ) == "missing-source-target"
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: occupiedURL.path
            ) == "missing-destination-target"
        )
    }

    @Test("A dangling symbolic link reserves its destination name during a move")
    func moveDoesNotReplaceDanglingSymbolicLink() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "shortcut")
        let destinationURL = destinationDirectory.appending(path: "shortcut")
        try FileManager.default.createSymbolicLink(
            atPath: sourceURL.path,
            withDestinationPath: "source-target"
        )
        try FileManager.default.createSymbolicLink(
            atPath: destinationURL.path,
            withDestinationPath: "destination-target"
        )

        do {
            _ = try await FileOperationService().moveItem(
                at: sourceURL,
                to: destinationDirectory
            )
            Issue.record("Expected a destination collision error.")
        } catch let error as FileOperationError {
            #expect(error == .destinationAlreadyExists(path: destinationURL.path))
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: sourceURL.path
            ) == "source-target"
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: destinationURL.path
            ) == "destination-target"
        )
    }

    @Test("A destination symlink cannot bypass descendant validation")
    func rejectsDirectoryCopyThroughDescendantSymlink() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeDirectory(named: "Folder", in: root)
        let childURL = try makeDirectory(named: "Child", in: sourceURL)
        let childAliasURL = root.appending(path: "Child Alias")
        try FileManager.default.createSymbolicLink(
            at: childAliasURL,
            withDestinationURL: childURL
        )

        do {
            _ = try await FileOperationService().copyItem(
                at: sourceURL,
                to: childAliasURL
            )
            Issue.record("Expected a recursive destination error.")
        } catch let error as FileOperationError {
            #expect(
                error == .cannotPlaceDirectoryInsideItself(
                    sourcePath: sourceURL.path,
                    destinationPath: childURL.path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("Moving through an alias of the current parent remains a no-op")
    func aliasedSameParentMoveDoesNothing() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let actualDirectory = try makeDirectory(named: "actual", in: root)
        let directoryAlias = root.appending(path: "actual-alias")
        try FileManager.default.createSymbolicLink(
            at: directoryAlias,
            withDestinationURL: actualDirectory
        )
        let sourceURL = actualDirectory.appending(path: "item.txt")
        try Data("kept".utf8).write(to: sourceURL)

        let outcome = try await FileOperationService().moveItem(
            at: sourceURL,
            to: directoryAlias
        )

        #expect(outcome == FileOperationOutcome(destinationURL: sourceURL, didChange: false))
        #expect(try readUTF8(sourceURL) == "kept")
    }

    @Test("A failed recursive copy removes every partial destination artifact")
    func failedCopyIsAtomic() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try makeDirectory(named: "Blocked", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        try Data("copied first".utf8).write(to: sourceURL.appending(path: "a-readable.txt"))
        let unreadableURL = sourceURL.appending(path: "z-unreadable.txt")
        try Data("private".utf8).write(to: unreadableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: unreadableURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: unreadableURL.path
            )
        }

        do {
            _ = try await FileOperationService().copyItem(
                at: sourceURL,
                to: destinationDirectory
            )
            Issue.record("Expected the unreadable item to fail the copy.")
        } catch let error as FileOperationError {
            guard case let .copyFailed(sourcePath, destinationPath, _) = error else {
                Issue.record("Expected copyFailed, received \(error).")
                return
            }
            #expect(sourcePath == sourceURL.path)
            #expect(destinationPath == destinationDirectory.appending(path: "Blocked").path)
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        let remainingItems = try FileManager.default.contentsOfDirectory(
            atPath: destinationDirectory.path
        )
        #expect(remainingItems.isEmpty)
    }

    @Test("Concurrent copies claim distinct names without losing data")
    func concurrentCopiesAreCollisionSafe() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "payload.dat")
        let sourceData = Data(repeating: 0xA5, count: 4_096)
        try sourceData.write(to: sourceURL)

        let outcomes = try await withThrowingTaskGroup(
            of: FileOperationOutcome.self,
            returning: [FileOperationOutcome].self
        ) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await FileOperationService().copyItem(
                        at: sourceURL,
                        to: destinationDirectory
                    )
                }
            }

            var outcomes: [FileOperationOutcome] = []
            for try await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        #expect(outcomes.count == 24)
        #expect(Set(outcomes.map(\.destinationURL)).count == 24)
        for outcome in outcomes {
            #expect(try Data(contentsOf: outcome.destinationURL) == sourceData)
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path)
                .contains(where: { $0.hasPrefix(".finallyexplorer-copy-") }) == false
        )
    }

    @Test("Concurrent moves to one name preserve both sources without overwriting")
    func concurrentMovesNeverOverwrite() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstSourceDirectory = try makeDirectory(named: "source-a", in: root)
        let secondSourceDirectory = try makeDirectory(named: "source-b", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let firstSource = firstSourceDirectory.appending(path: "shared.txt")
        let secondSource = secondSourceDirectory.appending(path: "shared.txt")
        let destination = destinationDirectory.appending(path: "shared.txt")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let results = await withTaskGroup(
            of: ConcurrentMoveResult.self,
            returning: [ConcurrentMoveResult].self
        ) { group in
            for source in [firstSource, secondSource] {
                group.addTask {
                    do {
                        return .success(
                            try await FileOperationService().moveItem(
                                at: source,
                                to: destinationDirectory
                            )
                        )
                    } catch let error as FileOperationError {
                        return .failure(error)
                    } catch {
                        return .unexpected(error.localizedDescription)
                    }
                }
            }

            var results: [ConcurrentMoveResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let successes = results.compactMap { result -> FileOperationOutcome? in
            guard case let .success(outcome) = result else { return nil }
            return outcome
        }
        let failures = results.compactMap { result -> FileOperationError? in
            guard case let .failure(error) = result else { return nil }
            return error
        }
        let unexpected = results.compactMap { result -> String? in
            guard case let .unexpected(message) = result else { return nil }
            return message
        }
        let remainingSources = [firstSource, secondSource].filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let remainingSource = try #require(remainingSources.first)
        let preservedContents: Set<String> = [
            try readUTF8(destination),
            try readUTF8(remainingSource),
        ]

        #expect(successes.count == 1)
        #expect(successes.first?.destinationURL == destination)
        #expect(failures == [.destinationAlreadyExists(path: destination.path)])
        #expect(unexpected.isEmpty)
        #expect(remainingSources.count == 1)
        #expect(preservedContents == ["first", "second"])
    }

    @Test("Copy suffixes fit at the file system's maximum name length")
    func maximumLengthFileNameCanBeCopiedAfterCollision() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceName = String(repeating: "a", count: 251) + ".txt"
        let sourceURL = sourceDirectory.appending(path: sourceName)
        let occupiedURL = destinationDirectory.appending(path: sourceName)
        try Data("new".utf8).write(to: sourceURL)
        try Data("existing".utf8).write(to: occupiedURL)

        let outcome = try await FileOperationService().copyItem(
            at: sourceURL,
            to: destinationDirectory
        )

        #expect(outcome.destinationURL.lastPathComponent.utf8.count <= 255)
        #expect(outcome.destinationURL.lastPathComponent.hasSuffix(" copy.txt"))
        #expect(try readUTF8(outcome.destinationURL) == "new")
        #expect(try readUTF8(occupiedURL) == "existing")
    }

    @Test("A cancelled operation exits before changing the file system")
    func respondsToCancellation() async throws {
        let root = try makeFileOperationTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDirectory = try makeDirectory(named: "source", in: root)
        let destinationDirectory = try makeDirectory(named: "destination", in: root)
        let sourceURL = sourceDirectory.appending(path: "cancelled.txt")
        let destinationURL = destinationDirectory.appending(path: "cancelled.txt")
        try Data("source".utf8).write(to: sourceURL)

        let gate = FileOperationStartGate()
        let task = Task {
            await gate.wait()
            return try await FileOperationService().copyItem(
                at: sourceURL,
                to: destinationDirectory
            )
        }

        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test("The internal transfer payload keeps its identity and custom type")
    func internalTransferPayloadKeepsIdentity() throws {
        let sourceURL = URL(filePath: "/tmp/internal-transfer.txt")
        let sourcePaneID = try #require(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")
        )
        let payload = InternalFileTransfer(
            sourceURL: sourceURL,
            sourcePaneID: sourcePaneID
        )
        #expect(payload.sourcePaneID == sourcePaneID)
        #expect(payload.id.sourceURL == sourceURL)
        #expect(payload.id.sourcePaneID == sourcePaneID)
        #expect(
            UTType.finallyExplorerInternalFileTransfer.identifier
                == "com.temelgunaydin.finallyexplorer.internal-file-transfer"
        )
        #expect(UTType.finallyExplorerInternalFileTransfer != .fileURL)
    }

    @Test("The private item provider advertises, decodes, and never exports a file URL")
    @MainActor
    func internalTransferPayloadLoadsFromItemProvider() async throws {
        let payload = InternalFileTransfer(
            sourceURL: URL(filePath: "/tmp/dragged-item.txt"),
            sourcePaneID: try #require(
                UUID(uuidString: "10000000-0000-0000-0000-000000000002")
            )
        )
        let provider = InternalFileTransferProvider.make(
            sourceURL: payload.sourceURL,
            sourcePaneID: payload.sourcePaneID
        )

        #expect(
            provider.hasItemConformingToTypeIdentifier(
                UTType.finallyExplorerInternalFileTransfer.identifier
            )
        )
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.data.identifier))
        #expect(
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                == false
        )

        let decoded = try #require(
            await InternalFileTransferProvider.load(from: [provider]).first
        )

        #expect(decoded == payload)
    }

    @Test("A forged public data provider cannot create an internal file transfer")
    @MainActor
    func forgedProviderCannotCreateInternalTransfer() async throws {
        let provider = NSItemProvider()
        let forgedEnvelope = Data(
            #"{"token":"30000000-0000-0000-0000-000000000001"}"#.utf8
        )
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.data.identifier,
            visibility: .all
        ) { completion in
            completion(forgedEnvelope, nil)
            return nil
        }

        let decoded = await InternalFileTransferProvider.load(from: [provider])

        #expect(decoded.isEmpty)
    }

    @Test("Drop action truth table prefers copying unless every source is local")
    func dropActionTruthTable() throws {
        let sourcePaneID = try #require(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        )
        let destinationPaneID = try #require(
            UUID(uuidString: "20000000-0000-0000-0000-000000000002")
        )
        let cases: [(
            name: String,
            sourcePaneIDs: [UUID],
            destinationPaneID: UUID,
            expected: InternalFileDropAction
        )] = [
            ("same pane", [sourcePaneID, sourcePaneID], sourcePaneID, .move),
            ("cross pane", [sourcePaneID], destinationPaneID, .copy),
            (
                "mixed identities",
                [sourcePaneID, destinationPaneID],
                destinationPaneID,
                .copy
            ),
            ("missing identities", [], destinationPaneID, .copy),
        ]

        for testCase in cases {
            let action = InternalFileDropAction(
                sourcePaneIDs: testCase.sourcePaneIDs,
                destinationPaneID: testCase.destinationPaneID
            )
            #expect(action == testCase.expected, "Case: \(testCase.name)")
        }
    }
}

private actor FileOperationStartGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilBlocked() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private enum ConcurrentMoveResult: Sendable {
    case success(FileOperationOutcome)
    case failure(FileOperationError)
    case unexpected(String)
}

private func makeFileOperationTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerFileOperationTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func makeDirectory(named name: String, in parent: URL) throws -> URL {
    let url = parent.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func readUTF8(_ url: URL) throws -> String {
    String(decoding: try Data(contentsOf: url), as: UTF8.self)
}
