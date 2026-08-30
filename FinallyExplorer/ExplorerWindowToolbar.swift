//
//  ExplorerWindowToolbar.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerWindowToolbar: ToolbarContent {
    let activeFolderTitle: String
    let paneCount: Int
    let isPreviewVisible: Bool
    let onTogglePreview: () -> Void
    let onResetView: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if paneCount == 1 {
                Button(
                    isPreviewVisible ? "Hide Preview" : "Show Preview",
                    systemImage: "sidebar.trailing",
                    action: onTogglePreview
                )
                .buttonStyle(ExplorerChromeActionButtonStyle())
                .help(
                    isPreviewVisible
                        ? "Hide the preview area"
                        : "Show the preview area"
                )
            } else {
                Button(
                    "Reset View",
                    systemImage: "rectangle",
                    action: onResetView
                )
                .buttonStyle(ExplorerChromeActionButtonStyle())
                .help("Keep the active pane and close the other panes")
            }

            ExplorerWindowStatus(
                activeFolderTitle: activeFolderTitle,
                paneCount: paneCount
            )
        }
    }
}

private struct ExplorerWindowStatus: View {
    let activeFolderTitle: String
    let paneCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Label(activeFolderTitle, systemImage: "folder.fill")
                .lineLimit(1)
                .frame(maxWidth: 240)

            Label(
                paneCount == 1 ? "1 pane" : "\(paneCount) panes",
                systemImage: paneCount == 1
                    ? "rectangle"
                    : "rectangle.split.2x1"
            )
        }
        .font(.system(.callout, design: .rounded).bold())
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(ExplorerTheme.chromeText)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
        }
    }
}
