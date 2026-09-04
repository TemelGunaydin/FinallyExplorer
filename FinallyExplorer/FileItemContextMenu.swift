//
//  FileItemContextMenu.swift
//  FinallyExplorer
//

import SwiftUI

struct FileItemContextMenu: View {
    @Environment(FileOperationCoordinator.self) private var fileOperations
    @Environment(NearbyTransferCoordinator.self) private var nearbyTransfers
    @Environment(TerminalApplicationCoordinator.self) private var terminalApplications
    @Environment(\.explorerTheme) private var theme

    let item: FileItem
    let sidebar: SidebarModel
    let onDismiss: () -> Void
    let onShowInfo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    FileItemIconView(item: item)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(ExplorerTheme.actionFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(item.isDirectory ? "Folder" : "File")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 4)
                }
                .padding(9)
                .background(theme.control, in: .rect(cornerRadius: 10))

                Divider()
                    .overlay(theme.divider)
                    .padding(.vertical, 4)

                ExplorerContextMenuActionButton(
                    title: "Cut",
                    systemImage: "scissors",
                    shortcut: "⌘X"
                ) {
                    perform {
                        fileOperations.cut([item.url])
                    }
                }

                ExplorerContextMenuActionButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C"
                ) {
                    perform {
                        fileOperations.copy([item.url])
                    }
                }

                ExplorerContextMenuActionButton(
                    title: "Rename",
                    systemImage: "pencil",
                    isEnabled: fileOperations.isPerforming == false
                ) {
                    perform {
                        fileOperations.requestRename(item.url)
                    }
                }

                ExplorerContextMenuActionButton(
                    title: "Compress to ZIP",
                    systemImage: "archivebox",
                    isEnabled: fileOperations.isPerforming == false
                ) {
                    perform {
                        fileOperations.compress(item.url)
                    }
                }

                Divider()
                    .overlay(theme.divider)
                    .padding(.vertical, 4)

                ShareLink(item: item.url) {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 18)
                        Text("Share")
                        Spacer(minLength: 12)
                    }
                }
                .buttonStyle(.plain)
                .explorerContextMenuRow()

                ExplorerContextMenuActionButton(
                    title: "Send to Nearby Device…",
                    systemImage: "person.2.wave.2"
                ) {
                    perform {
                        nearbyTransfers.prepareToSend([item.url])
                    }
                }

                ExplorerContextMenuActionButton(
                    title: "Get Info",
                    systemImage: "info.circle"
                ) {
                    perform(onShowInfo)
                }

                ExplorerContextMenuActionButton(
                    title: "Show in Finder",
                    systemImage: "folder"
                ) {
                    perform {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                }

                Divider()
                    .overlay(theme.divider)
                    .padding(.vertical, 4)

                FileItemFavoriteContextAction(
                    item: item,
                    sidebar: sidebar,
                    onDismiss: onDismiss
                )

                if item.isDirectory {
                    ExplorerContextMenuActionButton(
                        title: item.isHidden ? "Unhide Folder" : "Hide Folder",
                        systemImage: item.isHidden ? "eye" : "eye.slash",
                        isEnabled: fileOperations.isPerforming == false
                    ) {
                        perform {
                            fileOperations.setHidden(
                                item.isHidden == false,
                                for: item.url
                            )
                        }
                    }

                    ExplorerContextMenuActionButton(
                        title: "Paste Into Folder",
                        systemImage: "doc.on.clipboard",
                        shortcut: "⌘V",
                        isEnabled: fileOperations.canPaste
                    ) {
                        perform {
                            fileOperations.paste(into: item.url)
                        }
                    }

                    ForEach(terminalApplications.installedApplications) { application in
                        ExplorerContextMenuActionButton(
                            title: "Open in \(application.name)",
                            systemImage: "terminal",
                            isEnabled: terminalApplications.isOpening == false
                        ) {
                            perform {
                                terminalApplications.open(item.url, in: application)
                            }
                        }
                    }
                }

                Divider()
                    .overlay(theme.divider)
                    .padding(.vertical, 4)

                ExplorerContextMenuActionButton(
                    title: "Move to Trash",
                    systemImage: "trash",
                    shortcut: "⌘⌫",
                    isEnabled: fileOperations.isPerforming == false,
                    isDestructive: true
                ) {
                    perform {
                        fileOperations.requestTrashConfirmation(for: [item.url])
                    }
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .frame(width: 286)
        .frame(maxHeight: 560)
        .background(theme.elevatedPanel)
        .presentationBackground(theme.elevatedPanel)
        .presentationCornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(item.name)")
        .accessibilityIdentifier("file-item-context-menu")
    }

    private func perform(_ action: () -> Void) {
        onDismiss()
        action()
    }
}
