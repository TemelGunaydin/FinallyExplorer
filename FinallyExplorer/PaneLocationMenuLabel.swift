//
//  PaneLocationMenuLabel.swift
//  FinallyExplorer
//

import SwiftUI

/// Gives the location menu a full-size label so its entire pill is interactive.
struct PaneLocationMenu<MenuItems: View>: View {
    @Environment(\.explorerTheme) private var theme

    let title: String
    let systemImage: String
    let isCompact: Bool
    let menuItems: MenuItems

    init(
        title: String,
        systemImage: String,
        isCompact: Bool,
        @ViewBuilder menuItems: () -> MenuItems
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isCompact = isCompact
        self.menuItems = menuItems()
    }

    var body: some View {
        Menu {
            menuItems
        } label: {
            Label(title, systemImage: systemImage)
                .font(
                    isCompact
                        ? ExplorerTheme.actionFont
                        : ExplorerTheme.paneTitleFont
                )
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 12)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .frame(
            width: isCompact ? 170 : 320,
            height: isCompact ? 40 : 48
        )
        .contentShape(.rect)
        .background {
            ExplorerRaisedButtonSurface(
                cornerRadius: 11,
                pressedOverlay: theme.accentSoft.opacity(0.58)
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    theme.accent.opacity(0.34),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color.black.opacity(0.16),
            radius: 1,
            x: 0,
            y: 1
        )
        .shadow(
            color: theme.imperialPrimer.opacity(0.14),
            radius: 5,
            x: 0,
            y: 2
        )
        .accessibilityLabel("Current location: \(title)")
        .accessibilityHint("Choose a folder for this pane")
        .accessibilityIdentifier("pane-location-menu")
    }
}
