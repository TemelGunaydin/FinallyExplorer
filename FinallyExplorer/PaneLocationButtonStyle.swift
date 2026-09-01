//
//  PaneLocationButtonStyle.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneLocationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .fill(theme.imperialPrimer.opacity(0.72))
                    .offset(y: 4)

                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.accentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                theme.accent.opacity(
                                    configuration.isPressed ? 0.38 : 0.22
                                )
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(0.3),
                radius: 2,
                x: 0,
                y: 3
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.24),
                radius: 8,
                x: 0,
                y: 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
