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
        #expect(coordinator.moveToTrash(nil) == false)
        #expect(coordinator.setHidden(true, for: nil) == false)
        #expect(coordinator.cancelCurrentOperation() == false)
        #expect(coordinator.isPerforming == false)
        #expect(await service.operationCount() == 0)
    }

    @Test("Moving an item to Trash refreshes its parent and reports completion")
    func trashRefreshesParent() async {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let sourceURL = URL(filePath: "/tmp/Discard Me.txt")

        #expect(coordinator.moveToTrash(sourceURL))
        #expect(coordinator.statusMessage == "Moving item to Trash…")
        await coordinator.waitForCurrentOperation()

        #expect(await service.trashedSources() == [sourceURL])
        #expect(
            coordinator.directoryRefreshRevision(
                for: sourceURL.deletingLastPathComponent()
            ) == 1
        )
        #expect(coordinator.notice?.message == "Moved to Trash")
        #expect(coordinator.isPerforming == false)
        #expect(coordinator.isErrorPresented == false)
    }

    @Test("Only the newest file-operation notice may dismiss itself")
    func transientNoticeReplacementIsRaceSafe() async {
        let gate = FileOperationNoticeDelayGate()
        let coordinator = FileOperationCoordinator(
            service: ScriptedFileOperationService(),
            noticeDelay: {
                await gate.suspend()
                try Task.checkCancellation()
            }
        )

        coordinator.copy([URL(filePath: "/tmp/first.txt")])
        await gate.waitUntilBlockedRequestCount(1)
        let copiedNoticeID = coordinator.notice?.id
        #expect(coordinator.notice?.message == "Copied")

        coordinator.cut([URL(filePath: "/tmp/second.txt")])
        await gate.waitUntilBlockedRequestCount(2)
        #expect(coordinator.notice?.message == "Cut")
        #expect(coordinator.notice?.id != copiedNoticeID)

        await gate.resumeRequest(at: 0)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(
            coordinator.notice?.message == "Cut",
            "A canceled older dismissal must not erase newer feedback"
        )

        await gate.resumeRequest(at: 1)
        for _ in 0..<1_000 {
            if coordinator.notice == nil { break }
            await Task.yield()
        }
        #expect(coordinator.notice == nil)
    }

    @Test("Hiding a folder refreshes its parent and preserves request intent")
    func hideFolderRefreshesParent() async throws {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let directoryURL = URL(
            filePath: "/tmp/visible/folder",
            directoryHint: .isDirectory
        )

        #expect(coordinator.setHidden(true, for: directoryURL))
        #expect(coordinator.statusMessage == "Hiding folder…")
        await coordinator.waitForCurrentOperation()

        let request = try #require(await service.visibilityRequests().first)
        #expect(request.0 == directoryURL)
        #expect(request.1)
        #expect(
            coordinator.directoryRefreshRevision(
                for: directoryURL.deletingLastPathComponent()
            ) == 1
        )
        #expect(coordinator.directoryRefreshRevision(for: directoryURL) == 0)
    }

    @Test("Rename publishes its destination and refreshes only the parent")
    func renameRefreshesParentAndPublishesResult() async throws {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let sourceURL = URL(filePath: "/tmp/Before.txt")
        let destinationURL = URL(filePath: "/tmp/After.txt")

        coordinator.requestRename(sourceURL)
        #expect(coordinator.renameRequest?.sourceURL == sourceURL)
        #expect(coordinator.rename(sourceURL, to: "After.txt"))
        #expect(coordinator.renameRequest == nil)
        #expect(coordinator.statusMessage == "Renaming item…")

        await coordinator.waitForCurrentOperation()

        let request = try #require(await service.renames().first)
        #expect(request.0 == sourceURL)
        #expect(request.1 == "After.txt")
        #expect(coordinator.lastRenameResult?.sourceURL == sourceURL)
        #expect(coordinator.lastRenameResult?.destinationURL == destinationURL)
        #expect(coordinator.directoryRefreshRevision(for: URL(filePath: "/tmp")) == 1)
        #expect(coordinator.notice?.message == "Renamed")
    }

    @Test("A file-command cut pastes as a move and consumes the completed cut")
    func fileCommandCutMovesAndConsumesCompletedClipboard() async {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/source.txt")
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )
        let context = FileCommandContext(
            selectedURLs: [source],
            destinationDirectoryURL: destination,
            coordinator: coordinator
        )

        context.cutSelection()

        #expect(coordinator.clipboardOperation == .cut)
        #expect(coordinator.clipboardURLs == [source])
        #expect(context.canPaste)
        #expect(coordinator.paste(into: destination))
        #expect(coordinator.statusMessage == "Moving item…")
        await coordinator.waitForCurrentOperation()

        #expect(await service.movedSources() == [source])
        #expect(await service.copiedSources().isEmpty)
        #expect(coordinator.clipboardURLs.isEmpty)
        #expect(coordinator.clipboardOperation == nil)
        #expect(coordinator.canPaste == false)
        #expect(
            coordinator.directoryRefreshRevision(
                for: source.deletingLastPathComponent()
            ) == 1
        )
        #expect(coordinator.directoryRefreshRevision(for: destination) == 1)
    }

    @Test("A focused file command resolves selection and destination at action time")
    func focusedCommandDoesNotPasteIntoAStaleDirectory() async {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)
        let destination = root.appending(
            path: "Destination",
            directoryHint: .isDirectory
        )
        let source = root.appending(path: "Source.txt")
        let pane = WorkspacePaneState(
            id: UUID(),
            place: .favorite(SidebarFavorite(directoryURL: root))
        )
        let context = FileCommandContext(
            pane: pane,
            coordinator: coordinator
        )

        pane.selectedURL = source
        context.copySelection()
        pane.navigation.open(destination)
        context.paste()
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.clipboardURLs == [source])
        #expect(await service.copyDestinations() == [destination])
        #expect(coordinator.notice?.message == "Pasted")
    }

    @Test("Copy paste retains the copy clipboard for another destination")
    func copyPasteRetainsClipboard() async {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/source.txt")
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )

        coordinator.copy([source])

        #expect(coordinator.clipboardOperation == .copy)
        #expect(coordinator.notice?.message == "Copied")
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(await service.copiedSources() == [source])
        #expect(await service.movedSources().isEmpty)
        #expect(coordinator.clipboardURLs == [source])
        #expect(coordinator.clipboardOperation == .copy)
        #expect(coordinator.canPaste)
        #expect(coordinator.notice?.message == "Pasted")
    }

    @Test("File changes refresh only affected directory rows and recursive ancestors")
    func fileChangeRefreshScopeIsTargeted() async {
        let service = ScriptedFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let source = URL(filePath: "/tmp/source/Report.txt")
        let destination = URL(
            filePath: "/tmp/destination/nested",
            directoryHint: .isDirectory
        )
        let destinationParent = destination.deletingLastPathComponent()
        let unrelatedDirectory = URL(
            filePath: "/tmp/unrelated",
            directoryHint: .isDirectory
        )

        coordinator.copy([source])
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.directoryRefreshRevision(for: destination) == 1)
        #expect(coordinator.directoryRefreshRevision(for: destinationParent) == 0)
        #expect(coordinator.directoryRefreshRevision(for: unrelatedDirectory) == 0)
        #expect(coordinator.recursiveRefreshRevision(for: destination) == 1)
        #expect(coordinator.recursiveRefreshRevision(for: destinationParent) == 1)
        #expect(coordinator.recursiveRefreshRevision(for: unrelatedDirectory) == 0)
    }

    @Test("A cut paste retains sources whose moves fail")
    func partialCutPasteKeepsOnlyFailedSources() async {
        let firstSource = URL(filePath: "/tmp/first.txt")
        let secondSource = URL(filePath: "/tmp/second.txt")
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )
        let service = ScriptedFileOperationService(moveResults: [
            .success(
                FileOperationOutcome(
                    destinationURL: destination.appending(path: "first.txt"),
                    didChange: true
                )
            ),
            .failure(.rejected("second item could not be moved")),
        ])
        let coordinator = FileOperationCoordinator(service: service)

        coordinator.cut([firstSource, secondSource])
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(await service.movedSources() == [firstSource, secondSource])
        #expect(coordinator.clipboardURLs == [secondSource])
        #expect(coordinator.clipboardOperation == .cut)
        #expect(coordinator.canPaste)
        #expect(coordinator.isErrorPresented)
        #expect(coordinator.errorMessage == "second item could not be moved")
    }

    @Test("A no-op move does not consume a cut source")
    func noOpCutPasteRetainsSource() async {
        let source = URL(filePath: "/tmp/source.txt")
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )
        let service = ScriptedFileOperationService(moveResults: [
            .success(
                FileOperationOutcome(
                    destinationURL: source,
                    didChange: false
                )
            ),
        ])
        let coordinator = FileOperationCoordinator(service: service)

        coordinator.cut([source])
        #expect(coordinator.paste(into: destination))
        await coordinator.waitForCurrentOperation()

        #expect(await service.movedSources() == [source])
        #expect(coordinator.clipboardURLs == [source])
        #expect(coordinator.clipboardOperation == .cut)
        #expect(coordinator.isErrorPresented == false)
    }

    @Test("An in-flight cut cannot consume a newer clipboard")
    func cutPasteLeavesNewerClipboardUntouched() async {
        let service = BlockingFileOperationService()
        let coordinator = FileOperationCoordinator(service: service)
        let movedSource = URL(filePath: "/tmp/moved.txt")
        let replacementSource = URL(filePath: "/tmp/replacement.txt")
        let destination = URL(
            filePath: "/tmp/destination",
            directoryHint: .isDirectory
        )

        coordinator.cut([movedSource])
        #expect(coordinator.paste(into: destination))
        await service.waitUntilMoveStarted()

        coordinator.copy([replacementSource])
        await service.releaseMove()
        await coordinator.waitForCurrentOperation()

        #expect(await service.movedSources() == [movedSource])
        #expect(coordinator.clipboardURLs == [replacementSource])
        #expect(coordinator.clipboardOperation == .copy)
        #expect(coordinator.canPaste)
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
        #expect(
            successfulCoordinator.lastCreatedFolderURL
                == createdFolder.standardizedFileURL
        )
        #expect(
            successfulCoordinator.renameRequest?.sourceURL
                == createdFolder.standardizedFileURL
        )

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
        #expect(failingCoordinator.lastCreatedFolderURL == nil)
        #expect(failingCoordinator.renameRequest == nil)
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

private actor FileOperationNoticeDelayGate {
    private var nextRequestIndex = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func suspend() async {
        let requestIndex = nextRequestIndex
        nextRequestIndex += 1

        await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    func waitUntilBlockedRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(at index: Int) {
        continuations.removeValue(forKey: index)?.resume()
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
    private var moveResults: [Result<FileOperationOutcome, ScriptedFileOperationError>]
    private var createFolderResult: Result<
        FileOperationOutcome,
        ScriptedFileOperationError
    >?
    private var copySourceURLs: [URL] = []
    private var copyDestinationURLs: [URL] = []
    private var moveSourceURLs: [URL] = []
    private var createFolderCount = 0
    private var trashedSourceURLs: [URL] = []
    private var hiddenRequests: [(URL, Bool)] = []
    private var renameRequests: [(URL, String)] = []

    init(
        copyResults: [Result<FileOperationOutcome, ScriptedFileOperationError>] = [],
        moveResults: [Result<FileOperationOutcome, ScriptedFileOperationError>] = [],
        createFolderResult: Result<
            FileOperationOutcome,
            ScriptedFileOperationError
        >? = nil
    ) {
        self.copyResults = copyResults
        self.moveResults = moveResults
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
        copyDestinationURLs.append(destinationDirectoryURL)

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

    func trashItem(at sourceURL: URL) async throws -> FileOperationOutcome {
        trashedSourceURLs.append(sourceURL)
        return FileOperationOutcome(
            destinationURL: URL(filePath: "/tmp/.Trash")
                .appending(path: sourceURL.lastPathComponent),
            didChange: true
        )
    }

    func setHidden(
        _ hidden: Bool,
        for directoryURL: URL
    ) async throws -> FileOperationOutcome {
        hiddenRequests.append((directoryURL, hidden))
        return FileOperationOutcome(
            destinationURL: directoryURL,
            didChange: true
        )
    }

    func renameItem(
        at sourceURL: URL,
        to newName: String
    ) async throws -> FileOperationOutcome {
        renameRequests.append((sourceURL, newName))
        return FileOperationOutcome(
            destinationURL: sourceURL
                .deletingLastPathComponent()
                .appending(path: newName),
            didChange: true
        )
    }

    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        moveSourceURLs.append(sourceURL)

        if moveResults.isEmpty == false {
            return try moveResults.removeFirst().get()
        }

        return FileOperationOutcome(
            destinationURL: destinationDirectoryURL.appending(
                path: sourceURL.lastPathComponent
            ),
            didChange: true
        )
    }

    func operationCount() -> Int {
        copySourceURLs.count
            + moveSourceURLs.count
            + createFolderCount
            + trashedSourceURLs.count
            + hiddenRequests.count
            + renameRequests.count
    }

    func copiedSources() -> [URL] {
        copySourceURLs
    }

    func copyDestinations() -> [URL] {
        copyDestinationURLs
    }

    func movedSources() -> [URL] {
        moveSourceURLs
    }

    func trashedSources() -> [URL] {
        trashedSourceURLs
    }

    func visibilityRequests() -> [(URL, Bool)] {
        hiddenRequests
    }

    func renames() -> [(URL, String)] {
        renameRequests
    }
}

private actor BlockingFileOperationService: FileOperationServicing {
    private var copySourceURLs: [URL] = []
    private var copyContinuation: CheckedContinuation<Void, Never>?
    private var moveSourceURLs: [URL] = []
    private var moveContinuation: CheckedContinuation<Void, Never>?

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

    func trashItem(at sourceURL: URL) async throws -> FileOperationOutcome {
        FileOperationOutcome(
            destinationURL: URL(filePath: "/tmp/.Trash")
                .appending(path: sourceURL.lastPathComponent),
            didChange: true
        )
    }

    func setHidden(
        _ hidden: Bool,
        for directoryURL: URL
    ) async throws -> FileOperationOutcome {
        FileOperationOutcome(
            destinationURL: directoryURL,
            didChange: true
        )
    }

    func renameItem(
        at sourceURL: URL,
        to newName: String
    ) async throws -> FileOperationOutcome {
        FileOperationOutcome(
            destinationURL: sourceURL
                .deletingLastPathComponent()
                .appending(path: newName),
            didChange: true
        )
    }

    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        moveSourceURLs.append(sourceURL)
        await withCheckedContinuation { continuation in
            moveContinuation = continuation
        }
        try Task.checkCancellation()
        return FileOperationOutcome(
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

    func waitUntilMoveStarted() async {
        while moveContinuation == nil {
            await Task.yield()
        }
    }

    func releaseMove() {
        moveContinuation?.resume()
        moveContinuation = nil
    }

    func copiedSources() -> [URL] {
        copySourceURLs
    }

    func movedSources() -> [URL] {
        moveSourceURLs
    }
}
