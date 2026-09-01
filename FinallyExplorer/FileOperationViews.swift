//
//  FileOperationViews.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum InternalFileTransferProvider {
    // Canceled drags remain resolvable for a later retry, but the registry is
    // bounded so repeated abandoned drags cannot retain paths indefinitely.
    private static let maximumActiveTransferCount = 256
    private static var activeTransfers: [UUID: InternalFileTransfer] = [:]
    private static var transferOrder: [UUID] = []

    static func make(sourceURL: URL, sourcePaneID: UUID) -> NSItemProvider {
        let payload = InternalFileTransfer(
            sourceURL: sourceURL,
            sourcePaneID: sourcePaneID
        )
        let token = UUID()
        register(payload, for: token)

        let provider = NSItemProvider()
        guard let data = try? JSONEncoder().encode(
            InternalFileTransferEnvelope(token: token)
        ) else {
            removeTransfer(for: token)
            assertionFailure("Unable to encode an internal file transfer")
            return provider
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.finallyExplorerInternalFileTransfer.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.data.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func load(from providers: [NSItemProvider]) async -> [InternalFileTransfer] {
        var transfers: [InternalFileTransfer] = []
        transfers.reserveCapacity(providers.count)

        for provider in providers where provider.hasItemConformingToTypeIdentifier(
            UTType.data.identifier
        ) {
            if let transfer = try? await load(from: provider) {
                transfers.append(transfer)
            }
        }

        return transfers
    }

    private static func load(from provider: NSItemProvider) async throws -> InternalFileTransfer {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(
                forTypeIdentifier: UTType.data.identifier
            ) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: error ?? InternalFileTransferProviderError.missingData
                    )
                }
            }
        }
        let envelope = try JSONDecoder().decode(
            InternalFileTransferEnvelope.self,
            from: data
        )
        guard let transfer = activeTransfers[envelope.token] else {
            throw InternalFileTransferProviderError.unknownToken
        }
        removeTransfer(for: envelope.token)
        return transfer
    }

    private static func register(_ transfer: InternalFileTransfer, for token: UUID) {
        while activeTransfers.count >= maximumActiveTransferCount,
              let oldestToken = transferOrder.first {
            removeTransfer(for: oldestToken)
        }

        activeTransfers[token] = transfer
        transferOrder.append(token)
    }

    private static func removeTransfer(for token: UUID) {
        activeTransfers[token] = nil
        transferOrder.removeAll { $0 == token }
    }
}

private enum InternalFileTransferProviderError: Error {
    case missingData
    case unknownToken
}

private struct InternalFileTransferEnvelope: Codable {
    let token: UUID
}

private struct InternalFileInteractionModifier: ViewModifier {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(NearbyTransferCoordinator.self) private var nearbyTransfers

    let item: FileItem
    let paneID: UUID
    let sidebar: SidebarModel

    @State private var isInfoPresented = false

    func body(content: Content) -> some View {
        content
            .contentShape(.interaction, Rectangle())
            .contentShape(
                .dragPreview,
                RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .onDrag {
                InternalFileTransferProvider.make(
                    sourceURL: item.url,
                    sourcePaneID: paneID
                )
            }
            .modifier(
                InternalDirectoryRowDropModifier(
                    destinationDirectoryURL: item.isDirectory ? item.url : nil,
                    paneID: paneID
                )
            )
            .contextMenu {
                Button("Cut") {
                    fileOperations.cut([item.url])
                }

                Button("Copy") {
                    fileOperations.copy([item.url])
                }

                Button("Rename", systemImage: "pencil") {
                    fileOperations.requestRename(item.url)
                }
                .disabled(fileOperations.isPerforming)

                Divider()

                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button("Send to Nearby Device…", systemImage: "person.2.wave.2") {
                    nearbyTransfers.prepareToSend([item.url])
                }

                Button("Get Info", systemImage: "info.circle") {
                    isInfoPresented = true
                }

                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }

                if item.isDirectory {
                    Divider()

                    if let favorite = sidebar.favorite(for: item.url) {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            sidebar.remove(favorite)
                        }
                    } else if sidebar.canAdd(
                        itemURL: item.url,
                        isDirectory: true
                    ) {
                        Button("Add to Favorites", systemImage: "star") {
                            sidebar.add(itemURL: item.url, isDirectory: true)
                        }
                    }

                    Button(
                        item.isHidden ? "Unhide Folder" : "Hide Folder",
                        systemImage: item.isHidden ? "eye" : "eye.slash"
                    ) {
                        fileOperations.setHidden(
                            item.isHidden == false,
                            for: item.url
                        )
                    }
                    .disabled(fileOperations.isPerforming)

                    Button("Paste Into Folder") {
                        fileOperations.paste(into: item.url)
                    }
                    .disabled(fileOperations.canPaste == false)

                    TerminalContextMenuCommands(directoryURL: item.url)
                } else {
                    Divider()

                    if let favorite = sidebar.favorite(for: item.url) {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            sidebar.remove(favorite)
                        }
                    } else if sidebar.canAdd(
                        itemURL: item.url,
                        isDirectory: false
                    ) {
                        Button("Add to Favorites", systemImage: "star") {
                            sidebar.add(itemURL: item.url, isDirectory: false)
                        }
                    }
                }
            }
            .sheet(isPresented: $isInfoPresented) {
                FileInformationView(item: item)
            }
            .accessibilityAction(named: "Copy") {
                fileOperations.copy([item.url])
            }
    }
}

private struct InternalDirectoryRowDropModifier: ViewModifier {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(\.explorerTheme) private var theme

    let destinationDirectoryURL: URL?
    let paneID: UUID

    @State private var isDropTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let destinationDirectoryURL {
            let acceptsDrop = fileOperations.isPerforming == false

            content
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(theme.accent.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(theme.accent, lineWidth: 2)
                            }
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(
                    of: [.data],
                    isTargeted: $isDropTargeted
                ) { providers in
                    acceptDrop(
                        from: providers,
                        into: destinationDirectoryURL,
                        acceptsDrop: acceptsDrop
                    )
                }
        } else {
            content
        }
    }

    private func acceptDrop(
        from providers: [NSItemProvider],
        into destinationDirectoryURL: URL,
        acceptsDrop: Bool
    ) -> Bool {
        let internalProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.data.identifier
            )
        }
        guard acceptsDrop, internalProviders.isEmpty == false else { return false }

        isDropTargeted = false
        Task {
            let transfers = await InternalFileTransferProvider.load(
                from: internalProviders
            )
            guard transfers.isEmpty == false else { return }

            fileOperations.drop(
                transfers,
                into: destinationDirectoryURL,
                destinationPaneID: paneID
            )
        }
        return true
    }
}

private struct InternalFolderDropModifier: ViewModifier {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(\.explorerTheme) private var theme

    let destinationDirectoryURL: URL?
    let paneID: UUID
    let showsPasteCommand: Bool
    let showsTerminalCommands: Bool
    let showsNewFolderCommand: Bool
    let onCreateFolder: (() -> Void)?

    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        let acceptsDrop = destinationDirectoryURL != nil
            && fileOperations.isPerforming == false

        content
            .contentShape(Rectangle())
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.accent.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.accent, lineWidth: 2)
                        }
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(
                of: [.data],
                isTargeted: $isDropTargeted
            ) { providers in
                acceptDrop(from: providers, acceptsDrop: acceptsDrop)
            }
            .contextMenu {
                if showsNewFolderCommand {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        onCreateFolder?()
                    }
                    .disabled(
                        destinationDirectoryURL == nil
                            || fileOperations.isPerforming
                            || onCreateFolder == nil
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

    private func acceptDrop(
        from providers: [NSItemProvider],
        acceptsDrop: Bool
    ) -> Bool {
        guard let destinationDirectoryURL else { return false }
        let internalProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.data.identifier
            )
        }
        guard acceptsDrop, internalProviders.isEmpty == false else { return false }

        isDropTargeted = false
        Task {
            let transfers = await InternalFileTransferProvider.load(
                from: internalProviders
            )
            guard transfers.isEmpty == false else { return }

            fileOperations.drop(
                transfers,
                into: destinationDirectoryURL,
                destinationPaneID: paneID
            )
        }
        return true
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
    func internalFileInteraction(
        for item: FileItem,
        paneID: UUID,
        sidebar: SidebarModel
    ) -> some View {
        modifier(
            InternalFileInteractionModifier(
                item: item,
                paneID: paneID,
                sidebar: sidebar
            )
        )
    }

    func internalFolderDropTarget(
        destinationDirectoryURL: URL?,
        paneID: UUID,
        showsPasteCommand: Bool = true,
        showsTerminalCommands: Bool = false,
        showsNewFolderCommand: Bool = false,
        onCreateFolder: (() -> Void)? = nil
    ) -> some View {
        modifier(
            InternalFolderDropModifier(
                destinationDirectoryURL: destinationDirectoryURL,
                paneID: paneID,
                showsPasteCommand: showsPasteCommand,
                showsTerminalCommands: showsTerminalCommands,
                showsNewFolderCommand: showsNewFolderCommand,
                onCreateFolder: onCreateFolder
            )
        )
    }
}
