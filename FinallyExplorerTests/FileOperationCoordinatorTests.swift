//
//  FileOperationCoordinatorTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct FileOperationCoordinatorTests {
    @Test("Invalid or empty requests never start file-system work")
    func invalidRequestsAreRejectedSynchronously() async throws {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/folder/../source.txt")
        let duplicate = URL(filePath: "/tmp/source.txt")
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)
        let paneID = try #require(
            UUID(uuidString: "50000000-0000-0000-0000-000000000001")
        )

        coordinator.copy([source, duplicate, source])

        #expect(coordinator.clipboardURLs == [duplicate])
        #expect(coordinator.paste(into: nil) == false)
        #expect(coordinator.move([], into: destination) == false)
        #expect(
            coordinator.drop(
                [],
                into: destination,
                destinationPaneID: paneID
            ) == false
        )
        #expect(coordinator.createFolder(in: nil) == false)
        #expect(coordinator.cancelCurrentOperation() == false)
        #expect(coordinator.isPerforming == false)
        #expect(await service.operationCount() == 0)
    }

    @Test("Create-folder completion and failure leave coherent coordinator state")
    func createFolderRoutesOutcomeAndError() async {
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )
        let createdFolder = destination.appending(
            path: "New Folder",
            directoryHint: .isDirectory
        )
        let successfulService = ScriptedFileOperationService(
            createFolderResult: .success(
                FileOperationOutcome(
                    destinationURL: createdFolder,
                    didChange: true
                )
            )
        )
        let successfulCoordinator = FileOperationCoordinator(
            service: successfulService
        )

        #expect(successfulCoordinator.createFolder(in: destination))
        #expect(successfulCoordinator.statusMessage == "Creating folder…")
        await successfulCoordinator.waitForCurrentOperation()
        #expect(successfulCoordinator.completedOperationCount == 1)
        #expect(successfulCoordinator.isPerforming == false)
        #expect(successfulCoordinator.isErrorPresented == false)

        let failingService = ScriptedFileOperationService(
            createFolderResult: .failure(.rejected("creation rejected"))
        )
        let failingCoordinator = FileOperationCoordinator(service: failingService)

        #expect(failingCoordinator.createFolder(in: destination))
        await failingCoordinator.waitForCurrentOperation()
        #expect(failingCoordinator.completedOperationCount == 0)
        #expect(failingCoordinator.isPerforming == false)
        #expect(failingCoordinator.isErrorPresented)
        #expect(failingCoordinator.errorMessage == "creation rejected")
    }

    @Test("An active batch is immutable and rejects reentrant operations")
    func activeOperationRejectsReentrancyAndSnapshotsClipboard() async {
        let service = BlockingFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let firstSource = URL(filePath: "/tmp/first.txt")
        let replacementSource = URL(filePath: "/tmp/replacement.txt")
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)

        coordinator.copy([firstSource])
        #expect(coordinator.paste(into: destination))
        #expect(coordinator.isPerforming)
        #expect(coordinator.statusMessage == "Copying item…")
        #expect(coordinator.canPaste == false)

        coordinator.copy([replacementSource])
        #expect(coordinator.paste(into: destination) == false)
        #expect(coordinator.createFolder(in: destination) == false)

        await service.waitUntilCopyStarted()
        #expect(await service.copiedSources() == [firstSource])
        await service.releaseCopy()
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.clipboardURLs == [replacementSource])
        #expect(coordinator.isPerforming == false)
        #expect(coordinator.statusMessage == nil)
        #expect(coordinator.completedOperationCount == 1)
        #expect(coordinator.canPaste)
    }

    @Test("Cancellation resets state without presenting an error")
    func cancellationCleansUpCoordinatorState() async {
        let service = BlockingFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/source.txt")
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)

        coordinator.copy([source])
        #expect(coordinator.paste(into: destination))
        await service.waitUntilCopyStarted()

        #expect(coordinator.cancelCurrentOperation())
        await service.releaseCopy()
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.isPerforming == false)
        #expect(coordinator.statusMessage == nil)
        #expect(coordinator.completedOperationCount == 0)
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
        #expect(coordinator.cancelCurrentOperation() == false)
    }

    @Test("One invalid item does not prevent later items from completing")
    func partialBatchFailureContinuesRemainingItems() async {
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)
        let successfulDestination = destination.appending(path: "second.txt")
        let service = ScriptedFileOperationService(copyResults: [
            .failure(.rejected("first item is invalid")),
            .success(
                FileOperationOutcome(
                    destinationURL: successfulDestination,
                    didChange: true
                )
            ),
        ])
        let coordinator = FileOperationCoordinator(service: service)
        let firstSource = URL(filePath: "/tmp/first.txt")
        let secondSource = URL(filePath: "/tmp/second.txt")

        coordinator.copy([firstSource, secondSource])
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(await service.copiedSources() == [firstSource, secondSource])
        #expect(coordinator.completedOperationCount == 1)
        #expect(coordinator.isErrorPresented)
        #expect(coordinator.errorMessage == "first item is invalid")
        #expect(coordinator.isPerforming == false)
    }

    @Test("Large failure batches are summarized without unbounded alert text")
    func failureAggregationIsBounded() async {
        let sources = (0..<12).map { URL(filePath: "/tmp/item-\($0).txt") }
        let results = (0..<12).map {
            Result<FileOperationOutcome, ScriptedFileOperationError>.failure(
                .rejected("failure-\($0)")
            )
        }
        let service = ScriptedFileOperationService(copyResults: results)
        let coordinator = FileOperationCoordinator(service: service)
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)

        coordinator.copy(sources)
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(await service.copiedSources() == sources)
        #expect(coordinator.completedOperationCount == 0)
        #expect(coordinator.errorMessage.hasPrefix("12 items could not be processed:"))
        #expect(coordinator.errorMessage.contains("failure-0"))
        #expect(coordinator.errorMessage.contains("failure-7"))
        #expect(coordinator.errorMessage.contains("failure-8") == false)
        #expect(coordinator.errorMessage.contains("4 more failures"))
    }

    @Test("Starting a new operation clears stale failure state")
    func newOperationClearsPriorError() async {
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)
        let service = ScriptedFileOperationService(copyResults: [
            .failure(.rejected("old failure")),
            .success(
                FileOperationOutcome(
                    destinationURL: destination.appending(path: "second.txt"),
                    didChange: true
                )
            ),
        ])
        let coordinator = FileOperationCoordinator(service: service)

        coordinator.copy([URL(filePath: "/tmp/first.txt")])
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()
        #expect(coordinator.isErrorPresented)
        #expect(coordinator.errorMessage == "old failure")

        coordinator.copy([URL(filePath: "/tmp/second.txt")])
        #expect(coordinator.paste(into: destination))
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
        #expect(coordinator.completedOperationCount == 1)
    }

    @Test("Drop routing performs copies across panes and moves within one pane")
    func dropRoutingUsesResolvedAction() async throws {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/source.txt")
        let destination = URL(filePath: "/tmp/destination", directoryHint: .isDirectory)
        let sourcePaneID = try #require(
            UUID(uuidString: "60000000-0000-0000-0000-000000000001")
        )
        let destinationPaneID = try #require(
            UUID(uuidString: "60000000-0000-0000-0000-000000000002")
        )
        let transfer = InternalFileTransfer(
            sourceURL: source,
            sourcePaneID: sourcePaneID
        )

        #expect(
            coordinator.drop(
                [transfer],
                into: destination,
                destinationPaneID: destinationPaneID
            )
        )
        await coordinator.waitForCurrentOperation()
        #expect(await service.copiedSources() == [source])
        #expect(await service.movedSources().isEmpty)

        #expect(
            coordinator.drop(
                [transfer],
                into: destination,
                destinationPaneID: sourcePaneID
            )
        )
        await coordinator.waitForCurrentOperation()
        #expect(await service.movedSources() == [source])
    }
}

private enum ScriptedFileOperationError: LocalizedError, Sendable {
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case let .rejected(message):
            message
        }
    }
}

private actor ScriptedFileOperationService: FileOperationServicing {
    private var copyResults: [Result<FileOperationOutcome, ScriptedFileOperationError>]
    private var createFolderResult: Result<
        FileOperationOutcome,
        ScriptedFileOperationError
    >?
    private var copySourceURLs: [URL] = []
    private var moveSourceURLs: [URL] = []
    private var createFolderCount = 0

    init(
        copyResults: [Result<FileOperationOutcome, ScriptedFileOperationError>] = [],
        createFolderResult: Result<
            FileOperationOutcome,
            ScriptedFileOperationError
        >? = nil
    ) {
        self.copyResults = copyResults
        self.createFolderResult = createFolderResult
    }

    func createFolder(
        in destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        createFolderCount += 1

        if let createFolderResult {
            return try createFolderResult.get()
        }

        return FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(path: "New Folder"),
            didChange: true
        )
    }

    func copyItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        copySourceURLs.append(sourceURL)

        if copyResults.isEmpty == false {
            return try copyResults.removeFirst().get()
        }

        return FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(
                path: sourceURL.lastPathComponent
            ),
            didChange: true
        )
    }

    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        moveSourceURLs.append(sourceURL)
        return FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(
                path: sourceURL.lastPathComponent
            ),
            didChange: true
        )
    }

    func operationCount() -> Int {
        copySourceURLs.count + moveSourceURLs.count + createFolderCount
    }

    func copiedSources() -> [URL] {
        copySourceURLs
    }

    func movedSources() -> [URL] {
        moveSourceURLs
    }
}

private actor BlockingFileOperationService: FileOperationServicing {
    private var copySourceURLs: [URL] = []
    private var copyContinuation: CheckedContinuation<Void, Never>?

    func createFolder(
        in destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(path: "New Folder"),
            didChange: true
        )
    }

    func copyItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        copySourceURLs.append(sourceURL)
        await withCheckedContinuation { continuation in
            copyContinuation = continuation
        }
        try Task.checkCancellation()
        return FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(
                path: sourceURL.lastPathComponent
            ),
            didChange: true
        )
    }

    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(
                path: sourceURL.lastPathComponent
            ),
            didChange: true
        )
    }

    func waitUntilCopyStarted() async {
        while copyContinuation == nil {
            await Task.yield()
        }
    }

    func releaseCopy() {
        copyContinuation?.resume()
        copyContinuation = nil
    }

    func copiedSources() -> [URL] {
        copySourceURLs
    }
}
