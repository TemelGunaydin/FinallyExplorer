//
//  ExplorerPanePrimaryButtonStyle.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerPanePrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    let isCompact: Bool
    var usesAccentForeground = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                foregroundColor(isPressed: configuration.isPressed)
            )
            .padding(.horizontal, isCompact ? 0 : 14)
            .frame(width: isCompact ? 34 : nil, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.imperialPrimer.opacity(0.7))
                    .offset(y: 3)

                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.accentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(
                                theme.accent.opacity(
                                    configuration.isPressed ? 0.4 : 0.24
                                )
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(0.28),
                radius: 2,
                x: 0,
                y: 3
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.2),
                radius: 6,
                x: 0,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return theme.textTertiary }
        guard usesAccentForeground else { return theme.textPrimary }
        return isPressed ? theme.chromeText : theme.accent
    }
}
