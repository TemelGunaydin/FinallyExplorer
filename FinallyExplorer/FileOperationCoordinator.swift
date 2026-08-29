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

/// A scoped file-system change published after an operation completes.
///
/// Directory rows only need a reload when their direct children changed, while
/// recursive folder-size and search indexes need to observe descendants too.
private nonisolated struct FileSystemChange: Hashable, Sendable {
    let revision: Int
    let directlyAffectedDirectoryURLs: Set<URL>
}

@MainActor
@Observable
final class FileOperationCoordinator {
    private(set) var clipboardURLs: [URL] = []
    private(set) var clipboardOperation: FileClipboardOperation?
    private(set) var isPerforming = false
    private(set) var statusMessage: String?
    private(set) var completedOperationCount = 0
    private var latestFileSystemChange = FileSystemChange(
        revision: 0,
        directlyAffectedDirectoryURLs: []
    )

    var isErrorPresented = false
    private(set) var errorMessage = ""

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private let service: any FileOperationServicing
    @ObservationIgnored private var clipboardRevision = UUID()

    init(service: any FileOperationServicing = FileOperationService()) {
        self.service = service
    }

    var canPaste: Bool {
        clipboardURLs.isEmpty == false
            && clipboardOperation != nil
            && isPerforming == false
    }

    /// A revision for views showing this directory's *direct* children.
    func directoryRefreshRevision(for directoryURL: URL?) -> Int {
        guard let directoryURL else { return 0 }
        let normalizedDirectoryURL = Self.standardizedURL(directoryURL)

        return latestFileSystemChange.directlyAffectedDirectoryURLs.contains(
            normalizedDirectoryURL
        )
            ? latestFileSystemChange.revision
            : 0
    }

    /// A revision for data derived recursively from a folder, such as its
    /// total size or its FFF search index.
    func recursiveRefreshRevision(for directoryURL: URL?) -> Int {
        guard let directoryURL else { return 0 }
        let normalizedDirectoryURL = Self.standardizedURL(directoryURL)

        return latestFileSystemChange.directlyAffectedDirectoryURLs.contains {
            Self.isSameOrAncestor(normalizedDirectoryURL, of: $0)
        } ? latestFileSystemChange.revision : 0
    }

    func copy(_ urls: [URL]) {
        setClipboard(urls, operation: .copy)
    }

    func cut(_ urls: [URL]) {
        setClipboard(urls, operation: .cut)
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
                : nil
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
            cutClipboardSnapshot: nil
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

        return start(
            operation: action == .move ? .move : .copy,
            sources: transfers.map(\.sourceURL),
            destinationDirectoryURL: destinationDirectoryURL,
            cutClipboardSnapshot: nil
        )
    }

    @discardableResult
    func createFolder(in destinationDirectoryURL: URL?) -> Bool {
        guard let destinationDirectoryURL else { return false }

        return start(
            operation: .createFolder,
            sources: [],
            destinationDirectoryURL: destinationDirectoryURL,
            cutClipboardSnapshot: nil
        )
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
        cutClipboardSnapshot: ClipboardSnapshot?
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

        operationTask = Task(name: operation.taskName) { [weak self] in
            guard let self else { return }
            await perform(
                operation: operation,
                sources: sources,
                destinationDirectoryURL: destinationDirectoryURL,
                cutClipboardSnapshot: cutClipboardSnapshot
            )
        }

        return true
    }

    private func perform(
        operation: Operation,
        sources: [URL],
        destinationDirectoryURL: URL,
        cutClipboardSnapshot: ClipboardSnapshot?
    ) async {
        var didChange = false
        var successfullyMovedCutSources: Set<URL> = []
        var directlyAffectedDirectoryURLs: Set<URL> = []

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
        }

        do {
            switch operation {
            case .createFolder:
                let outcome = try await service.createFolder(
                    in: destinationDirectoryURL
                )
                didChange = outcome.didChange

                if outcome.didChange {
                    directlyAffectedDirectoryURLs.insert(
                        Self.standardizedURL(destinationDirectoryURL)
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
                        case .createFolder:
                            preconditionFailure("Create Folder does not process source items.")
                        }

                        didChange = didChange || outcome.didChange

                        if outcome.didChange {
                            directlyAffectedDirectoryURLs.insert(
                                Self.standardizedURL(destinationDirectoryURL)
                            )

                            if operation == .move {
                                directlyAffectedDirectoryURLs.insert(
                                    Self.standardizedURL(
                                        sourceURL.deletingLastPathComponent()
                                    )
                                )
                            }
                        }

                        if operation == .move,
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
        }
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []

        return urls.compactMap { url in
            let standardizedURL = Self.standardizedURL(url)
            return seen.insert(standardizedURL).inserted ? standardizedURL : nil
        }
    }

    private func publishFileSystemChange(
        directlyAffecting directoryURLs: Set<URL>
    ) async {
        await FolderSizeCache.shared.invalidateRecursively(
            affectedBy: directoryURLs
        )
        completedOperationCount += 1
        latestFileSystemChange = FileSystemChange(
            revision: completedOperationCount,
            directlyAffectedDirectoryURLs: directoryURLs
        )
    }

    private static func standardizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isSameOrAncestor(_ ancestor: URL, of descendant: URL) -> Bool {
        let ancestorPath = normalizedPath(of: ancestor)
        let descendantPath = normalizedPath(of: descendant)

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
        case createFolder

        var requiresSources: Bool {
            switch self {
            case .copy, .move:
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
    let selectedURLs: [URL]
    let destinationDirectoryURL: URL?
    let coordinator: FileOperationCoordinator

    var canCopy: Bool {
        selectedURLs.isEmpty == false
    }

    var canCut: Bool {
        selectedURLs.isEmpty == false
    }

    var canPaste: Bool {
        destinationDirectoryURL != nil && coordinator.canPaste
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
}

extension FocusedValues {
    @Entry var fileCommandContext: FileCommandContext?
}
