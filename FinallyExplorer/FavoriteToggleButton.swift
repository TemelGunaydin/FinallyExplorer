//
//  FavoriteToggleButton.swift
//  FinallyExplorer
//

import SwiftUI

struct FavoriteToggleButton: View {
    @Environment(\.explorerTheme) private var theme

    let item: FileItem
    let sidebar: SidebarModel

    @State private var isHovered = false

    private func actionTitle(for status: SidebarFavoriteStatus) -> String {
        switch status {
        case .custom:
            "Remove \(item.name) from Favorites"
        case .builtIn:
            "Remove \(item.name) from Sidebar"
        case .hiddenBuiltIn:
            "Add \(item.name) to Sidebar"
        case .available:
            "Add \(item.name) to Favorites"
        }
    }

    var body: some View {
        let status = sidebar.favoriteStatus(for: item.url)
        let actionTitle = actionTitle(for: status)

        Button {
            switch status {
            case let .custom(favorite):
                sidebar.remove(favorite)
            case let .builtIn(place):
                sidebar.hideBuiltInPlace(place)
            case let .hiddenBuiltIn(place):
                sidebar.restoreBuiltInPlace(place)
            case .available:
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
                        ? theme.warmHighlight
                        : theme.textTertiary
                )
                .frame(width: 24, height: 30)
                .background(
                    isHovered
                        ? theme.control.opacity(0.78)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(actionTitle)
        .accessibilityLabel(actionTitle)
        .accessibilityIdentifier("favorite-toggle-\(item.url.path(percentEncoded: false))")
    }
}
