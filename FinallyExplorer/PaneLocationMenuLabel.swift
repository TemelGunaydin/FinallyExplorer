//
//  PaneLocationMenuLabel.swift
//  FinallyExplorer
//

import SwiftUI

/// Keeps the current path outside `Menu`'s label. macOS constrains menu labels
/// to one line, which otherwise clips the path when a `VStack` is used there.
struct PaneLocationMenu<MenuItems: View>: View {
    let title: String
    let systemImage: String
    let directoryURL: URL?
    let isCompact: Bool
    let menuItems: MenuItems

    init(
        title: String,
        systemImage: String,
        directoryURL: URL?,
        isCompact: Bool,
        @ViewBuilder menuItems: () -> MenuItems
    ) {
        self.title = title
        self.systemImage = systemImage
        self.directoryURL = directoryURL
        self.isCompact = isCompact
        self.menuItems = menuItems()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Menu {
                menuItems
            } label: {
                Label(title, systemImage: systemImage)
                    .font(
                        isCompact
                            ? ExplorerTheme.actionFont
                            : ExplorerTheme.paneTitleFont
                    )
                    .foregroundStyle(ExplorerTheme.textPrimary)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("pane-location-menu")

            if let directoryURL {
                Text(abbreviatedPath(for: directoryURL))
                    .font(.caption)
                    .foregroundStyle(ExplorerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("pane-location-path")
            }
        }
        .frame(width: isCompact ? 170 : 320, alignment: .leading)
        .frame(minHeight: isCompact ? 40 : 48, alignment: .leading)
        .padding(.horizontal, 12)
        .background(
            ExplorerTheme.accentSoft,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    ExplorerTheme.accent.opacity(0.22),
                    lineWidth: 0.75
                )
        }
    }

    private func abbreviatedPath(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .path(percentEncoded: false)

        if path == homePath {
            return "~"
        }

        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + String(path.dropFirst(homePath.count))
    }
}
