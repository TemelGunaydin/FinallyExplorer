//
//  FileInformationView.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

struct FileInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.explorerTheme) private var theme

    let item: FileItem

    @State private var folderSize: Int64?
    @State private var isCalculatingFolderSize = false
    @State private var didFailToCalculateFolderSize = false

    private var kindDescription: String {
        if item.isDirectory { return "Folder" }

        let fileExtension = item.url.pathExtension
        return fileExtension.isEmpty
            ? "File"
            : "\(fileExtension.uppercased()) file"
    }

    private var sizeDescription: String {
        let fileSize = item.isDirectory ? folderSize : item.fileSize

        guard let fileSize else {
            if item.isDirectory, isCalculatingFolderSize {
                return "Calculating…"
            }
            return didFailToCalculateFolderSize ? "Unavailable" : "—"
        }

        return ByteCountFormatter.string(
            fromByteCount: fileSize,
            countStyle: .file
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                FileItemIconView(item: item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(ExplorerTheme.paneTitleFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)

                    Text(kindDescription)
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Divider()
                .overlay(theme.divider)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                informationRow("Location", value: item.url.deletingLastPathComponent().path())
                informationRow("Size", value: sizeDescription)
                informationRow(
                    "Modified",
                    value: item.modificationDate?.formatted(
                        date: .long,
                        time: .shortened
                    ) ?? "—"
                )
                informationRow("Hidden", value: item.isHidden ? "Yes" : "No")
            }

            HStack {
                Button("Show in Finder", systemImage: "finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(theme.elevatedPanel)
        .accessibilityIdentifier("file-info-panel")
        .task(id: item.url) {
            await calculateFolderSizeIfNeeded()
        }
    }

    private func informationRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            Text(value)
                .font(.callout)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityIdentifier(
                    "file-info-\(title.lowercased())-value"
                )
        }
    }

    private func calculateFolderSizeIfNeeded() async {
        guard item.isDirectory else { return }

        folderSize = nil
        didFailToCalculateFolderSize = false
        isCalculatingFolderSize = true

        do {
            let size = try await FolderSizeCache.shared.size(of: item.url)
            try Task.checkCancellation()
            folderSize = size
        } catch is CancellationError {
            return
        } catch {
            didFailToCalculateFolderSize = true
        }

        isCalculatingFolderSize = false
    }
}
