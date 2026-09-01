//
//  FileOperationServiceCreateFolderTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct FileOperationServiceCreateFolderTests {
    @Test("An empty destination receives New Folder")
    func createsNewFolder() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await FileOperationService().createFolder(in: root)
        var isDirectory: ObjCBool = false

        #expect(outcome.didChange)
        #expect(outcome.destinationURL.lastPathComponent == "New Folder")
        #expect(
            FileManager.default.fileExists(
                atPath: outcome.destinationURL.path,
                isDirectory: &isDirectory
            )
        )
        #expect(isDirectory.boolValue)
    }

    @Test("Occupied names advance from New Folder to New Folder 2 and beyond")
    func usesUniqueFolderNamesWithoutOverwriting() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstCandidate = root.appending(path: "New Folder")
        let secondCandidate = root.appending(path: "New Folder 2", directoryHint: .isDirectory)
        let originalData = Data("keep me".utf8)
        try originalData.write(to: firstCandidate)
        try FileManager.default.createDirectory(
            at: secondCandidate,
            withIntermediateDirectories: false
        )

        let outcome = try await FileOperationService().createFolder(in: root)

        #expect(outcome.destinationURL.lastPathComponent == "New Folder 3")
        #expect(try Data(contentsOf: firstCandidate) == originalData)
        #expect(FileManager.default.fileExists(atPath: secondCandidate.path))
        #expect(FileManager.default.fileExists(atPath: outcome.destinationURL.path))
    }

    @Test("A confirmed folder name is created exactly and never overwritten")
    func createsConfirmedNameWithoutOverwriting() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try await FileOperationService().createFolder(
            in: root,
            named: "Project Notes"
        )

        #expect(outcome.destinationURL.lastPathComponent == "Project Notes")
        #expect(FileManager.default.fileExists(atPath: outcome.destinationURL.path))

        await #expect(
            throws: FileOperationError.destinationAlreadyExists(
                path: outcome.destinationURL.path
            )
        ) {
            try await FileOperationService().createFolder(
                in: root,
                named: "Project Notes"
            )
        }
    }

    @Test("A missing destination is rejected without creating intermediate folders")
    func rejectsMissingDestination() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingDestination = root.appending(
            path: "Missing",
            directoryHint: .isDirectory
        )

        do {
            _ = try await FileOperationService().createFolder(in: missingDestination)
            Issue.record("Expected a missing destination error.")
        } catch let error as FileOperationError {
            #expect(
                error == .destinationNotFound(
                    path: missingDestination
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                        .path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(FileManager.default.fileExists(atPath: missingDestination.path) == false)
    }

    @Test("A destination file is rejected")
    func rejectsDestinationFile() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let destinationFile = root.appending(path: "destination.txt")
        try Data("unchanged".utf8).write(to: destinationFile)

        do {
            _ = try await FileOperationService().createFolder(in: destinationFile)
            Issue.record("Expected a destination type error.")
        } catch let error as FileOperationError {
            #expect(
                error == .destinationIsNotDirectory(
                    path: destinationFile
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                        .path
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(try String(contentsOf: destinationFile, encoding: .utf8) == "unchanged")
    }

    @Test("A non-file destination URL is rejected")
    func rejectsNonFileURL() async throws {
        let destinationURL = try #require(URL(string: "https://example.com/folder"))

        do {
            _ = try await FileOperationService().createFolder(in: destinationURL)
            Issue.record("Expected a local destination URL error.")
        } catch let error as FileOperationError {
            #expect(
                error == .destinationMustBeFileURL(
                    value: destinationURL.absoluteString
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }
    }

    @Test("A file URL with a remote host is rejected as a destination")
    func rejectsNonLocalFileURL() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destinationURL = try #require(
            URL(string: "file://example.com\(root.path(percentEncoded: true))")
        )

        do {
            _ = try await FileOperationService().createFolder(in: destinationURL)
            Issue.record("Expected a non-local destination URL error.")
        } catch let error as FileOperationError {
            #expect(
                error == .destinationMustBeFileURL(
                    value: destinationURL.absoluteString
                )
            )
        } catch {
            Issue.record("Expected FileOperationError, received \(error).")
        }

        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: "New Folder").path
            ) == false
        )
    }

    @Test("A dangling symbolic link reserves the New Folder name")
    func danglingSymbolicLinkAdvancesFolderName() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let occupiedURL = root.appending(path: "New Folder")
        try FileManager.default.createSymbolicLink(
            atPath: occupiedURL.path,
            withDestinationPath: "missing-target"
        )

        let outcome = try await FileOperationService().createFolder(in: root)

        #expect(outcome.destinationURL.lastPathComponent == "New Folder 2")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: occupiedURL.path
            ) == "missing-target"
        )
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(
                atPath: outcome.destinationURL.path,
                isDirectory: &isDirectory
            )
        )
        #expect(isDirectory.boolValue)
    }

    @Test("Concurrent folder creation claims every unique sequence number")
    func concurrentCreationIsCollisionSafe() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcomes = try await withThrowingTaskGroup(
            of: FileOperationOutcome.self,
            returning: [FileOperationOutcome].self
        ) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await FileOperationService().createFolder(in: root)
                }
            }

            var outcomes: [FileOperationOutcome] = []
            for try await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        #expect(outcomes.count == 16)
        #expect(Set(outcomes.map(\.destinationURL)).count == 16)
        for outcome in outcomes {
            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(
                    atPath: outcome.destinationURL.path,
                    isDirectory: &isDirectory
                )
            )
            #expect(isDirectory.boolValue)
        }
    }

    @Test("Cancellation is observed before the file system changes")
    func cancellationPreventsCreation() async throws {
        let root = try makeCreateFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = CreateFolderStartGate()
        let task = Task {
            await gate.wait()
            return try await FileOperationService().createFolder(in: root)
        }

        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: "New Folder").path
            ) == false
        )
    }
}

private actor CreateFolderStartGate {
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

private func makeCreateFolderTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerCreateFolderTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false
    )
    return directoryURL
}
