//
//  SidebarRestorePopover.swift
//  FinallyExplorer
//

import SwiftUI

struct SidebarRestorePopover: View {
    @Environment(\.explorerTheme) private var theme

    let hiddenPlaces: [SidebarBuiltInPlace]
    let onRestore: (SidebarBuiltInPlace) -> Void
    let onRestoreAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sidebar Items", systemImage: "sidebar.left")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text("Choose an item to add back.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            VStack(spacing: 6) {
                ForEach(hiddenPlaces) { place in
                    Button(action: { onRestore(place) }) {
                        Label(place.title, systemImage: place.systemImage)
                            .font(ExplorerTheme.actionFont)
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .contentShape(.rect)
                            .background(
                                theme.control,
                                in: .rect(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "sidebar-restore-\(place.rawValue)"
                    )
                }
            }

            Divider()
                .overlay(theme.divider)

            Button(
                "Restore All Defaults",
                systemImage: "arrow.counterclockwise",
                action: onRestoreAll
            )
            .buttonStyle(.link)
            .foregroundStyle(theme.accent)
            .accessibilityIdentifier("sidebar-restore-all-button")
        }
        .padding(14)
        .frame(width: 280)
        .background(theme.elevatedPanel)
        .presentationBackground(theme.elevatedPanel)
    }
}
