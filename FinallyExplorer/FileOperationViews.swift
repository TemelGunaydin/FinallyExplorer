//
//  FileOperationViews.swift
//  FinallyExplorer
//

import SwiftUI

private struct InternalFileInteractionModifier: ViewModifier {
    @Environment(FileOperationCoordinator.self) private var fileOperations

    let item: FileItem
    let paneID: UUID

    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        let acceptsDrop = item.isDirectory && fileOperations.isPerforming == false

        content
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .draggable(
                InternalFileTransfer.self,
                item: InternalFileTransfer(
                    sourceURL: item.url,
                    sourcePaneID: paneID
                )
            )
            .dragConfiguration(
                DragConfiguration(
                    operationsWithinApp: .init(
                        allowCopy: true,
                        allowMove: true,
                        allowDelete: false
                    ),
                    operationsOutsideApp: .init(
                        allowCopy: false,
                        allowMove: false,
                        allowDelete: false
                    )
                )
            )
            .dropDestination(
                for: InternalFileTransfer.self,
                isEnabled: acceptsDrop
            ) { transfers, _ in
                fileOperations.drop(
                    transfers,
                    into: item.url,
                    destinationPaneID: paneID
                )
            }
            .dropConfiguration { session in
                dropConfiguration(for: session, acceptsDrop: acceptsDrop)
            }
            .onDropSessionUpdated { session in
                updateDropTarget(session, acceptsDrop: acceptsDrop)
            }
            .contextMenu {
                Button("Copy") {
                    fileOperations.copy([item.url])
                }

                if item.isDirectory {
                    Button("Paste Into Folder") {
                        fileOperations.paste(into: item.url)
                    }
                    .disabled(fileOperations.canPaste == false)

                    TerminalContextMenuCommands(directoryURL: item.url)
                }
            }
            .accessibilityAction(named: "Copy") {
                fileOperations.copy([item.url])
            }
    }

    private func dropConfiguration(
        for session: DropSession,
        acceptsDrop: Bool
    ) -> DropConfiguration {
        guard acceptsDrop else {
            return DropConfiguration(operation: .forbidden)
        }

        let sourcePaneIDs = session.localSession?
            .draggedItemIDs(for: InternalFileTransfer.ID.self)
            .map(\.sourcePaneID) ?? []
        let action = InternalFileDropAction(
            sourcePaneIDs: sourcePaneIDs,
            destinationPaneID: paneID
        )

        return DropConfiguration(operation: action == .move ? .move : .copy)
    }

    private func updateDropTarget(_ session: DropSession, acceptsDrop: Bool) {
        guard acceptsDrop else {
            isDropTargeted = false
            return
        }

        switch session.phase {
        case .entering, .active:
            isDropTargeted = true
        case .exiting, .ended, .dataTransferCompleted:
            isDropTargeted = false
        @unknown default:
            isDropTargeted = false
        }
    }
}

private struct InternalFolderDropModifier: ViewModifier {
    @Environment(FileOperationCoordinator.self) private var fileOperations

    let destinationDirectoryURL: URL?
    let paneID: UUID
    let showsPasteCommand: Bool
    let showsTerminalCommands: Bool
    let showsNewFolderCommand: Bool

    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        let acceptsDrop = destinationDirectoryURL != nil
            && fileOperations.isPerforming == false

        content
            .contentShape(Rectangle())
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(
                for: InternalFileTransfer.self,
                isEnabled: acceptsDrop
            ) { transfers, _ in
                fileOperations.drop(
                    transfers,
                    into: destinationDirectoryURL,
                    destinationPaneID: paneID
                )
            }
            .dropConfiguration { session in
                dropConfiguration(for: session, acceptsDrop: acceptsDrop)
            }
            .onDropSessionUpdated { session in
                updateDropTarget(session, acceptsDrop: acceptsDrop)
            }
            .contextMenu {
                if showsNewFolderCommand {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        fileOperations.createFolder(in: destinationDirectoryURL)
                    }
                    .disabled(
                        destinationDirectoryURL == nil || fileOperations.isPerforming
                    )

                    Divider()
                }

                if showsPasteCommand {
                    Button("Paste") {
                        fileOperations.paste(into: destinationDirectoryURL)
                    }
                    .disabled(
                        destinationDirectoryURL == nil || fileOperations.canPaste == false
                    )
                }

                if showsTerminalCommands, let destinationDirectoryURL {
                    TerminalContextMenuCommands(directoryURL: destinationDirectoryURL)
                }
            }
    }

    private func dropConfiguration(
        for session: DropSession,
        acceptsDrop: Bool
    ) -> DropConfiguration {
        guard acceptsDrop else {
            return DropConfiguration(operation: .forbidden)
        }

        let sourcePaneIDs = session.localSession?
            .draggedItemIDs(for: InternalFileTransfer.ID.self)
            .map(\.sourcePaneID) ?? []
        let action = InternalFileDropAction(
            sourcePaneIDs: sourcePaneIDs,
            destinationPaneID: paneID
        )

        return DropConfiguration(operation: action == .move ? .move : .copy)
    }

    private func updateDropTarget(_ session: DropSession, acceptsDrop: Bool) {
        guard acceptsDrop else {
            isDropTargeted = false
            return
        }

        switch session.phase {
        case .entering, .active:
            isDropTargeted = true
        case .exiting, .ended, .dataTransferCompleted:
            isDropTargeted = false
        @unknown default:
            isDropTargeted = false
        }
    }
}

private struct TerminalContextMenuCommands: View {
    @Environment(TerminalApplicationCoordinator.self) private var terminalApplications

    let directoryURL: URL

    var body: some View {
        if terminalApplications.installedApplications.isEmpty == false {
            Divider()

            Menu("Open in Terminal", systemImage: "terminal") {
                ForEach(terminalApplications.installedApplications) { application in
                    Button(application.name) {
                        terminalApplications.open(directoryURL, in: application)
                    }
                }
            }
            .disabled(terminalApplications.isOpening)
        }
    }
}

extension View {
    func internalFileInteraction(for item: FileItem, paneID: UUID) -> some View {
        modifier(InternalFileInteractionModifier(item: item, paneID: paneID))
    }

    func internalFolderDropTarget(
        destinationDirectoryURL: URL?,
        paneID: UUID,
        showsPasteCommand: Bool = true,
        showsTerminalCommands: Bool = false,
        showsNewFolderCommand: Bool = false
    ) -> some View {
        modifier(
            InternalFolderDropModifier(
                destinationDirectoryURL: destinationDirectoryURL,
                paneID: paneID,
                showsPasteCommand: showsPasteCommand,
                showsTerminalCommands: showsTerminalCommands,
                showsNewFolderCommand: showsNewFolderCommand
            )
        )
    }
}
