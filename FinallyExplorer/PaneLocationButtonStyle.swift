//
//  PaneLocationButtonStyle.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneLocationButtonStyle: ButtonStyle {
    @Environment(\.explorerTheme) private var theme

    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                isCompact
                    ? .system(.headline, design: .rounded).bold()
                    : .system(.title2, design: .rounded).bold()
            )
            .foregroundStyle(theme.textPrimary)
            .frame(
                width: isCompact ? 148 : 236,
                height: isCompact ? 38 : 44
            )
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.imperialPrimer.opacity(0.38))
                    .offset(y: 3)

                ExplorerRaisedButtonSurface(
                    cornerRadius: 12,
                    pressedOverlay: configuration.isPressed
                        ? theme.accentSoft.opacity(0.78)
                        : theme.accentSoft.opacity(0.34)
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.accent.opacity(0.44), lineWidth: 0.9)
            }
            .shadow(
                color: Color.black.opacity(0.22),
                radius: 2,
                x: 0,
                y: 2
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.2),
                radius: 6,
                x: 0,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
