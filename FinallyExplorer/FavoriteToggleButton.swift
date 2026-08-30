//
//  FavoriteToggleButton.swift
//  FinallyExplorer
//

import SwiftUI

struct FavoriteToggleButton: View {
    let item: FileItem
    let sidebar: SidebarModel

    @State private var isHovered = false

    private func actionTitle(for status: SidebarFavoriteStatus) -> String {
        switch status {
        case .custom:
            "Remove \(item.name) from Favorites"
        case .builtIn:
            "\(item.name) is a built-in Favorite"
        case .available:
            "Add \(item.name) to Favorites"
        }
    }

    var body: some View {
        let status = sidebar.favoriteStatus(for: item.url)
        let actionTitle = actionTitle(for: status)
        let canToggle = status != .builtIn

        Button {
            if case let .custom(favorite) = status {
                sidebar.remove(favorite)
            } else if case .available = status {
                sidebar.add(
                    itemURL: item.url,
                    isDirectory: item.isDirectory
                )
            }
        } label: {
            Image(systemName: status.isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    status.isFavorite
                        ? ExplorerTheme.warmHighlight
                        : ExplorerTheme.textTertiary
                )
                .frame(width: 24, height: 30)
                .background(
                    isHovered && canToggle
                        ? ExplorerTheme.control.opacity(0.78)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canToggle == false)
        .opacity(canToggle || status.isFavorite ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .help(actionTitle)
        .accessibilityLabel(actionTitle)
        .accessibilityIdentifier("favorite-toggle-\(item.url.path(percentEncoded: false))")
    }
}
