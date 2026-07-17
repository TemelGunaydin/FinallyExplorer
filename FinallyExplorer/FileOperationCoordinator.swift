//
//  FileOperationCoordinator.swift
//  FinallyExplorer
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FileOperationCoordinator {
    private(set) var clipboardURLs: [URL] = []
    private(set) var isPerforming = false
    private(set) var statusMessage: String?
    private(set) var completedOperationCount = 0

    var isErrorPresented = false
    private(set) var errorMessage = ""

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private let service: any FileOperationServicing

    init(service: any FileOperationServicing = FileOperationService()) {
        self.service = service
    }

    var canPaste: Bool {
        clipboardURLs.isEmpty == false && isPerforming == false
    }

    func copy(_ urls: [URL]) {
        clipboardURLs = Self.uniqueStandardizedURLs(urls)
    }

    @discardableResult
    func paste(into destinationDirectoryURL: URL?) -> Bool {
        guard let destinationDirectoryURL, canPaste else { return false }

        return start(
            operation: .copy,
            sources: clipboardURLs,
            destinationDirectoryURL: destinationDirectoryURL
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
            destinationDirectoryURL: destinationDirectoryURL
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
            destinationDirectoryURL: destinationDirectoryURL
        )
    }

    @discardableResult
    func createFolder(in destinationDirectoryURL: URL?) -> Bool {
        guard let destinationDirectoryURL else { return false }

        return start(
            operation: .createFolder,
            sources: [],
            destinationDirectoryURL: destinationDirectoryURL
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
        destinationDirectoryURL: URL
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
                destinationDirectoryURL: destinationDirectoryURL
            )
        }

        return true
    }

    private func perform(
        operation: Operation,
        sources: [URL],
        destinationDirectoryURL: URL
    ) async {
        var didChange = false

        defer {
            if didChange {
                completedOperationCount += 1
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
            return
        } catch {
            errorMessage = error.localizedDescription
            isErrorPresented = true
        }
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []

        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            return seen.insert(standardizedURL).inserted ? standardizedURL : nil
        }
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
}

@MainActor
struct FileCommandContext {
    let selectedURLs: [URL]
    let destinationDirectoryURL: URL?
    let coordinator: FileOperationCoordinator

    var canCopy: Bool {
        selectedURLs.isEmpty == false
    }

    var canPaste: Bool {
        destinationDirectoryURL != nil && coordinator.canPaste
    }

    func copySelection() {
        guard canCopy else { return }
        coordinator.copy(selectedURLs)
    }

    func paste() {
        guard canPaste else { return }
        coordinator.paste(into: destinationDirectoryURL)
    }
}

extension FocusedValues {
    @Entry var fileCommandContext: FileCommandContext?
}
