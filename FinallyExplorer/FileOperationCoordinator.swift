//
//  FileOperationCoordinator.swift
//  FinallyExplorer
//

import Foundation
import Observation
import SwiftUI

/// Describes how the current in-app clipboard should be pasted.
///
/// A cut clipboard is intentionally kept separate from drag-and-drop moves:
/// only a paste that originated from a cut is allowed to consume its sources.
nonisolated enum FileClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}

@MainActor
@Observable
final class FileOperationCoordinator {
    private(set) var clipboardURLs: [URL] = []
    private(set) var clipboardOperation: FileClipboardOperation?
    private(set) var isPerforming = false
    private(set) var statusMessage: String?
    private(set) var notice: FileOperationNotice?
    private(set) var completedOperationCount = 0
    var renameRequest: FileRenameRequest?
    private(set) var trashConfirmationURLs: [URL] = []
    private(set) var lastRenameResult: FileRenameResult?
    private(set) var lastCreatedFolderURL: URL?
    private var directoryRevisionByPath: [String: Int] = [:]

    var isErrorPresented = false
    private(set) var errorMessage = ""

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var noticeDismissalTask: Task<Void, Never>?
    @ObservationIgnored private let service: any FileOperationServicing
    @ObservationIgnored private let noticeDelay: @Sendable () async throws -> Void
    @ObservationIgnored private var clipboardRevision = UUID()

    init(
        service: any FileOperationServicing = FileOperationService(),
        noticeDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .seconds(2.2))
        }
    ) {
        self.service = service
        self.noticeDelay = noticeDelay
    }

    deinit {
        operationTask?.cancel()
        noticeDismissalTask?.cancel()
    }

    var canPaste: Bool {
        clipboardURLs.isEmpty == false
            && clipboardOperation != nil
            && isPerforming == false
    }

    /// A revision for views showing this directory's *direct* children.
    func directoryRefreshRevision(for directoryURL: URL?) -> Int {
        guard let directoryURL else { return 0 }
        return directoryRevisionByPath[
            Self.normalizedPath(of: Self.standardizedURL(directoryURL))
        ] ?? 0
    }

    /// A revision for data derived recursively from a folder, such as its
    /// total size or its FFF search index.
    func recursiveRefreshRevision(for directoryURL: URL?) -> Int {
        guard let directoryURL else { return 0 }
        let directoryPath = Self.normalizedPath(
            of: Self.standardizedURL(directoryURL)
        )

        return directoryRevisionByPath.reduce(into: 0) { revision, change in
            guard Self.isSameOrAncestorPath(
                directoryPath,
                of: change.key
            ) else {
                return
            }

            revision = max(revision, change.value)
        }
    }

    func recordExternalChange(
        directlyAffecting directoryURL: URL,
        message: String,
        systemImage: String
    ) async {
        await publishFileSystemChange(
            directlyAffecting: [Self.standardizedURL(directoryURL)]
        )
        presentNotice(message: message, systemImage: systemImage)
    }

    func presentExternalNotice(message: String, systemImage: String) {
        presentNotice(message: message, systemImage: systemImage)
    }

    func copy(_ urls: [URL]) {
        setClipboard(urls, operation: .copy)

        guard clipboardURLs.isEmpty == false else { return }
        presentNotice(
            message: Self.completedMessage(
                singular: "Copied",
                itemCount: clipboardURLs.count
            ),
            systemImage: "doc.on.doc.fill"
        )
    }

    func cut(_ urls: [URL]) {
        setClipboard(urls, operation: .cut)

        guard clipboardURLs.isEmpty == false else { return }
        presentNotice(
            message: Self.completedMessage(
                singular: "Cut",
                itemCount: clipboardURLs.count
            ),
            systemImage: "scissors"
        )
    }

    @discardableResult
    func paste(into destinationDirectoryURL: URL?) -> Bool {
        guard let destinationDirectoryURL,
              let clipboardOperation,
              canPaste else {
            return false
        }

        let clipboardSnapshot = ClipboardSnapshot(
            urls: clipboardURLs,
            operation: clipboardOperation,
            revision: clipboardRevision
        )

        return start(
            operation: clipboardOperation == .cut ? .move : .copy,
            sources: clipboardSnapshot.urls,
            destinationDirectoryURL: destinationDirectoryURL,
            cutClipboardSnapshot: clipboardOperation == .cut
                ? clipboardSnapshot
                : nil,
            completionMessage: Self.completedMessage(
                singular: clipboardOperation == .cut ? "Moved" : "Pasted",
                itemCount: clipboardSnapshot.urls.count
            ),
            completionSystemImage: clipboardOperation == .cut
                ? "arrow.right.doc.on.clipboard"
                : "doc.on.clipboard.fill"
        )
    }

    @discardableResult
    func move(
        _ transfers: [InternalFileTransfer],
        into destinationDirectoryURL: URL?
    ) -> Bool {
        guard let destinationDirectoryURL else { return false }

        return start(
            operation: .move,
            sources: transfers.map(\.sourceURL),
            destinationDirectoryURL: destinationDirectoryURL,
            cutClipboardSnapshot: nil,
            completionMessage: Self.completedMessage(
                singular: "Moved",
                itemCount: transfers.count
            ),
            completionSystemImage: "arrow.right.doc.on.clipboard"
        )
    }

    @discardableResult
    func drop(
        _ transfers: [InternalFileTransfer],
        into destinationDirectoryURL: URL?,
        destinationPaneID: UUID
    ) -> Bool {
        guard let destinationDirectoryURL, transfers.isEmpty == false else {
            return false
        }

        let action = InternalFileDropAction(
            sourcePaneIDs: transfers.map(\.sourcePaneID),
            destinationPaneID: destinationPaneID
        )

        let operation: Operation = action == .move ? .move : .copy
        return start(
            operation: operation,
            sources: transfers.map(\.sourceURL),
            destinationDirectoryURL: destinationDirectoryURL,
            cutClipboardSnapshot: nil,
            completionMessage: Self.completedMessage(
                singular: operation.isMove ? "Moved" : "Copied",
                itemCount: transfers.count
            ),
            completionSystemImage: operation.isMove
                ? "arrow.right.doc.on.clipboard"
                : "doc.on.doc.fill"
        )
    }

    @discardableResult
    func createFolder(
        in destinationDirectoryURL: URL?,
        suggestedName: String = "New Folder"
    ) -> Bool {
        guard let destinationDirectoryURL,
              isPerforming == false,
              renameRequest == nil else {
            return false
        }

        lastCreatedFolderURL = nil
        renameRequest = FileRenameRequest(
            newFolderIn: destinationDirectoryURL,
            suggestedName: suggestedName
        )
        return true
    }

    @discardableResult
    func moveToTrash(_ sourceURL: URL?) -> Bool {
        guard let sourceURL else { return false }
        return moveToTrash([sourceURL])
    }

    @discardableResult
    func moveToTrash(_ sourceURLs: [URL]) -> Bool {
        let sourceURLs = Self.uniqueTrashRootURLs(sourceURLs)
        guard let firstSourceURL = sourceURLs.first else { return false }

        return start(
            operation: .trash,
            sources: sourceURLs,
            destinationDirectoryURL: firstSourceURL
                .deletingLastPathComponent(),
            cutClipboardSnapshot: nil,
            completionMessage: sourceURLs.count == 1
                ? "Moved to Trash"
                : "Moved \(sourceURLs.count) items to Trash",
            completionSystemImage: "trash.fill"
        )
    }

    @discardableResult
    func requestTrashConfirmation(for sourceURLs: [URL]) -> Bool {
        let sourceURLs = Self.uniqueTrashRootURLs(sourceURLs)
        guard sourceURLs.isEmpty == false,
              isPerforming == false,
              trashConfirmationURLs.isEmpty else {
            return false
        }

        trashConfirmationURLs = sourceURLs
        return true
    }

    func cancelTrashConfirmation() {
        trashConfirmationURLs = []
    }

    @discardableResult
    func confirmTrash() -> Bool {
        let sourceURLs = trashConfirmationURLs
        trashConfirmationURLs = []
        return moveToTrash(sourceURLs)
    }

    @discardableResult
    func setHidden(_ hidden: Bool, for directoryURL: URL?) -> Bool {
        guard let directoryURL else { return false }

        return start(
            operation: .setHidden(hidden),
            sources: [directoryURL],
            destinationDirectoryURL: directoryURL.deletingLastPathComponent(),
            cutClipboardSnapshot: nil,
            completionMessage: hidden ? "Folder hidden" : "Folder unhidden",
            completionSystemImage: hidden ? "eye.slash.fill" : "eye.fill"
        )
    }

    func requestRename(_ sourceURL: URL?) {
        guard let sourceURL, isPerforming == false else { return }
        renameRequest = FileRenameRequest(sourceURL: sourceURL)
    }

    func cancelRename(_ request: FileRenameRequest? = nil) {
        if let request, renameRequest?.id != request.id {
            return
        }
        renameRequest = nil
    }

    @discardableResult
    func commit(_ request: FileRenameRequest, with name: String) -> Bool {
        guard renameRequest?.id == request.id else { return false }

        switch request.intent {
        case .renameExistingItem:
            return rename(request.sourceURL, to: name)

        case let .createFolder(destinationDirectoryURL):
            let started = start(
                operation: .createFolder(name),
                sources: [],
                destinationDirectoryURL: destinationDirectoryURL,
                cutClipboardSnapshot: nil,
                completionMessage: "Folder created",
                completionSystemImage: "folder.badge.plus"
            )
            if started {
                renameRequest = nil
            }
            return started
        }
    }

    @discardableResult
    func rename(_ sourceURL: URL, to newName: String) -> Bool {
        let started = start(
            operation: .rename(newName),
            sources: [sourceURL.standardizedFileURL],
            destinationDirectoryURL: sourceURL
                .deletingLastPathComponent()
                .standardizedFileURL,
            cutClipboardSnapshot: nil,
            completionMessage: "Renamed",
            completionSystemImage: "pencil"
        )

        if started {
            renameRequest = nil
        }
        return started
    }

    /// Requests cancellation and lets the current operation unwind safely.
    /// FileManager calls are synchronous, so cancellation takes effect at the
    /// next safe boundary before another item or a staged copy is committed.
    @discardableResult
    func cancelCurrentOperation() -> Bool {
        guard let operationTask else { return false }
        operationTask.cancel()
        return true
    }

    /// Allows lifecycle owners and tests to await state cleanup without polling.
    func waitForCurrentOperation() async {
        let task = operationTask
        await task?.value
    }

    private func start(
        operation: Operation,
        sources: [URL],
        destinationDirectoryURL: URL,
        cutClipboardSnapshot: ClipboardSnapshot?,
        completionMessage: String,
        completionSystemImage: String
    ) -> Bool {
        let sources = Self.uniqueStandardizedURLs(sources)

        guard isPerforming == false,
              operation.requiresSources == false || sources.isEmpty == false else {
            return false
        }

        isPerforming = true
        statusMessage = operation.statusMessage(itemCount: sources.count)
        isErrorPresented = false
        errorMessage = ""

        if case .createFolder = operation {
            lastCreatedFolderURL = nil
        }

        operationTask = Task(name: operation.taskName) { [weak self] in
            guard let self else { return }
            await perform(
                operation: operation,
                sources: sources,
                destinationDirectoryURL: destinationDirectoryURL,
                cutClipboardSnapshot: cutClipboardSnapshot,
                completionMessage: completionMessage,
                completionSystemImage: completionSystemImage
            )
        }

        return true
    }

    private func perform(
        operation: Operation,
        sources: [URL],
        destinationDirectoryURL: URL,
        cutClipboardSnapshot: ClipboardSnapshot?,
        completionMessage: String,
        completionSystemImage: String
    ) async {
        var didChange = false
        var successfullyMovedCutSources: Set<URL> = []
        var directlyAffectedDirectoryURLs: Set<URL> = []
        var completedRenameResult: FileRenameResult?
        var completedCreatedFolderURL: URL?

        defer {
            if let cutClipboardSnapshot {
                consumeSuccessfullyMovedCutSources(
                    successfullyMovedCutSources,
                    matching: cutClipboardSnapshot
                )
            }

            isPerforming = false
            statusMessage = nil
            operationTask = nil

            if let completedCreatedFolderURL {
                lastCreatedFolderURL = completedCreatedFolderURL
            }
        }

        do {
            switch operation {
            case let .createFolder(name):
                let outcome = try await service.createFolder(
                    in: destinationDirectoryURL,
                    named: name
                )
                didChange = outcome.didChange

                if outcome.didChange {
                    completedCreatedFolderURL = Self.standardizedURL(
                        outcome.destinationURL
                    )
                    directlyAffectedDirectoryURLs.insert(
                        Self.standardizedURL(destinationDirectoryURL)
                    )
                }
            case .trash:
                var failureMessages: [String] = []

                for sourceURL in sources {
                    try Task.checkCancellation()

                    do {
                        let outcome = try await service.trashItem(at: sourceURL)
                        didChange = didChange || outcome.didChange

                        if outcome.didChange {
                            directlyAffectedDirectoryURLs.insert(
                                Self.standardizedURL(
                                    sourceURL.deletingLastPathComponent()
                                )
                            )
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failureMessages.append(error.localizedDescription)
                    }
                }

                if failureMessages.isEmpty == false {
                    errorMessage = Self.errorMessage(for: failureMessages)
                    isErrorPresented = true
                }
            case let .setHidden(hidden):
                guard let directoryURL = sources.first else { return }
                let outcome = try await service.setHidden(
                    hidden,
                    for: directoryURL
                )
                didChange = outcome.didChange

                if outcome.didChange {
                    directlyAffectedDirectoryURLs.insert(
                        Self.standardizedURL(
                            directoryURL.deletingLastPathComponent()
                        )
                    )
                }
            case let .rename(newName):
                guard let sourceURL = sources.first else { return }
                let outcome = try await service.renameItem(
                    at: sourceURL,
                    to: newName
                )
                didChange = outcome.didChange

                if outcome.didChange {
                    directlyAffectedDirectoryURLs.insert(
                        Self.standardizedURL(
                            sourceURL.deletingLastPathComponent()
                        )
                    )
                    completedRenameResult = FileRenameResult(
                        sourceURL: sourceURL,
                        destinationURL: outcome.destinationURL
                    )
                }
            case .copy, .move:
                var failureMessages: [String] = []

                for sourceURL in sources {
                    try Task.checkCancellation()

                    do {
                        let outcome: FileOperationOutcome
                        switch operation {
                        case .copy:
                            outcome = try await service.copyItem(
                                at: sourceURL,
                                to: destinationDirectoryURL
                            )
                        case .move:
                            outcome = try await service.moveItem(
                                at: sourceURL,
                                to: destinationDirectoryURL
                            )
                        case .createFolder, .trash, .setHidden, .rename:
                            preconditionFailure(
                                "This operation does not process copy or move sources."
                            )
                        }

                        didChange = didChange || outcome.didChange

                        if outcome.didChange {
                            directlyAffectedDirectoryURLs.insert(
                                Self.standardizedURL(destinationDirectoryURL)
                            )

                            if operation.isMove {
                                directlyAffectedDirectoryURLs.insert(
                                    Self.standardizedURL(
                                        sourceURL.deletingLastPathComponent()
                                    )
                                )
                            }
                        }

                        if operation.isMove,
                           cutClipboardSnapshot != nil,
                           outcome.didChange {
                            successfullyMovedCutSources.insert(sourceURL)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failureMessages.append(error.localizedDescription)
                    }
                }

                if failureMessages.isEmpty == false {
                    errorMessage = Self.errorMessage(for: failureMessages)
                    isErrorPresented = true
                }
            }

            try Task.checkCancellation()
        } catch is CancellationError {
            // A partially completed batch still changed the file system and
            // must invalidate only the folders it actually touched.
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }

        if didChange {
            await publishFileSystemChange(
                directlyAffecting: directlyAffectedDirectoryURLs
            )
            lastRenameResult = completedRenameResult

            if isErrorPresented == false {
                presentNotice(
                    message: completionMessage,
                    systemImage: completionSystemImage
                )
            }
        }
    }

    private func presentNotice(message: String, systemImage: String) {
        noticeDismissalTask?.cancel()

        let newNotice = FileOperationNotice(
            message: message,
            systemImage: systemImage
        )
        notice = newNotice
        let noticeDelay = noticeDelay

        noticeDismissalTask = Task { @MainActor [weak self] in
            do {
                try await noticeDelay()
                try Task.checkCancellation()
            } catch {
                return
            }

            guard let self, self.notice?.id == newNotice.id else { return }
            self.notice = nil
            self.noticeDismissalTask = nil
        }
    }

    private static func completedMessage(
        singular: String,
        itemCount: Int
    ) -> String {
        itemCount == 1 ? singular : "\(singular) \(itemCount) items"
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []

        return urls.compactMap { url in
            let standardizedURL = Self.standardizedURL(url)
            return seen.insert(standardizedURL).inserted ? standardizedURL : nil
        }
    }

    /// If both a directory and one of its descendants are selected (possible
    /// in global search), trash only the directory. Processing the descendant
    /// afterward would report a false failure because its path is already gone.
    private static func uniqueTrashRootURLs(_ urls: [URL]) -> [URL] {
        let uniqueURLs = uniqueStandardizedURLs(urls)

        return uniqueURLs.filter { candidate in
            uniqueURLs.contains { other in
                other != candidate && isSameOrAncestor(other, of: candidate)
            } == false
        }
    }

    private func publishFileSystemChange(
        directlyAffecting directoryURLs: Set<URL>
    ) async {
        await FolderSizeCache.shared.invalidateRecursively(
            affectedBy: directoryURLs
        )
        completedOperationCount += 1
        for directoryURL in directoryURLs {
            directoryRevisionByPath[
                Self.normalizedPath(of: Self.standardizedURL(directoryURL))
            ] = completedOperationCount
        }
    }

    private static func standardizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isSameOrAncestor(_ ancestor: URL, of descendant: URL) -> Bool {
        isSameOrAncestorPath(
            normalizedPath(of: ancestor),
            of: normalizedPath(of: descendant)
        )
    }

    private static func isSameOrAncestorPath(
        _ ancestorPath: String,
        of descendantPath: String
    ) -> Bool {

        if ancestorPath == "/" {
            return descendantPath.hasPrefix("/")
        }

        return descendantPath == ancestorPath
            || descendantPath.hasPrefix(ancestorPath + "/")
    }

    private static func normalizedPath(of url: URL) -> String {
        var path = url.path(percentEncoded: false)

        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }

    private func setClipboard(
        _ urls: [URL],
        operation: FileClipboardOperation
    ) {
        let urls = Self.uniqueStandardizedURLs(urls)
        clipboardURLs = urls
        clipboardOperation = urls.isEmpty ? nil : operation
        clipboardRevision = UUID()
    }

    /// Removes only the sources that were actually moved by the matching cut
    /// request. If the user copied or cut something else while the move was in
    /// flight, that newer clipboard remains completely untouched.
    private func consumeSuccessfullyMovedCutSources(
        _ successfullyMovedSources: Set<URL>,
        matching snapshot: ClipboardSnapshot
    ) {
        guard successfullyMovedSources.isEmpty == false,
              snapshot.operation == .cut,
              clipboardOperation == .cut,
              clipboardRevision == snapshot.revision else {
            return
        }

        clipboardURLs.removeAll { successfullyMovedSources.contains($0) }

        if clipboardURLs.isEmpty {
            clipboardOperation = nil
        }

        clipboardRevision = UUID()
    }

    private static func errorMessage(for failureMessages: [String]) -> String {
        guard failureMessages.count > 1 else {
            return failureMessages.first ?? ""
        }

        let displayedFailures = failureMessages.prefix(8)
        var message = "\(failureMessages.count) items could not be processed:\n\n"
        message += displayedFailures.map { "• \($0)" }.joined(separator: "\n\n")

        if failureMessages.count > displayedFailures.count {
            message += "\n\n• \(failureMessages.count - displayedFailures.count) more failures"
        }

        return message
    }

    private enum Operation: Sendable {
        case copy
        case move
        case createFolder(String)
        case trash
        case setHidden(Bool)
        case rename(String)

        var isMove: Bool {
            if case .move = self {
                true
            } else {
                false
            }
        }

        var requiresSources: Bool {
            switch self {
            case .copy, .move, .trash, .setHidden, .rename:
                true
            case .createFolder:
                false
            }
        }

        var taskName: String {
            switch self {
            case .copy:
                "Copy files"
            case .move:
                "Move files"
            case .createFolder:
                "Create folder"
            case .trash:
                "Move item to Trash"
            case let .setHidden(hidden):
                hidden ? "Hide folder" : "Unhide folder"
            case .rename:
                "Rename item"
            }
        }

        func statusMessage(itemCount: Int) -> String {
            switch (self, itemCount) {
            case (.copy, 1):
                "Copying item…"
            case (.copy, _):
                "Copying \(itemCount) items…"
            case (.move, 1):
                "Moving item…"
            case (.move, _):
                "Moving \(itemCount) items…"
            case (.createFolder, _):
                "Creating folder…"
            case (.trash, 1):
                "Moving item to Trash…"
            case (.trash, _):
                "Moving \(itemCount) items to Trash…"
            case let (.setHidden(hidden), _):
                hidden ? "Hiding folder…" : "Unhiding folder…"
            case (.rename, _):
                "Renaming item…"
            }
        }
    }

    private struct ClipboardSnapshot: Sendable {
        let urls: [URL]
        let operation: FileClipboardOperation
        let revision: UUID
    }
}

@MainActor
struct FileCommandContext {
    let coordinator: FileOperationCoordinator

    private let selectedURLsProvider: () -> [URL]
    private let destinationDirectoryURLProvider: () -> URL?

    init(
        selectedURLs: [URL],
        destinationDirectoryURL: URL?,
        coordinator: FileOperationCoordinator
    ) {
        self.coordinator = coordinator
        selectedURLsProvider = { selectedURLs }
        destinationDirectoryURLProvider = { destinationDirectoryURL }
    }

    init(
        pane: WorkspacePaneState,
        coordinator: FileOperationCoordinator
    ) {
        self.coordinator = coordinator
        selectedURLsProvider = { pane.selectedCommandURLs }
        destinationDirectoryURLProvider = { pane.displayedDirectory }
    }

    private var selectedURLs: [URL] {
        selectedURLsProvider()
    }

    private var destinationDirectoryURL: URL? {
        destinationDirectoryURLProvider()
    }

    var canCopy: Bool {
        selectedURLs.isEmpty == false
    }

    var canCut: Bool {
        selectedURLs.isEmpty == false
    }

    var canPaste: Bool {
        destinationDirectoryURL != nil && coordinator.canPaste
    }

    var canRename: Bool {
        selectedURLs.count == 1 && coordinator.isPerforming == false
    }

    var canRequestTrash: Bool {
        selectedURLs.isEmpty == false
            && coordinator.isPerforming == false
            && coordinator.trashConfirmationURLs.isEmpty
    }

    func copySelection() {
        guard canCopy else { return }
        coordinator.copy(selectedURLs)
    }

    func cutSelection() {
        guard canCut else { return }
        coordinator.cut(selectedURLs)
    }

    func paste() {
        guard canPaste else { return }
        coordinator.paste(into: destinationDirectoryURL)
    }

    func renameSelection() {
        guard canRename else { return }
        coordinator.requestRename(selectedURLs.first)
    }

    func requestTrashSelection() {
        guard canRequestTrash else { return }
        coordinator.requestTrashConfirmation(for: selectedURLs)
    }
}

extension FocusedValues {
    @Entry var fileCommandContext: FileCommandContext?
}
