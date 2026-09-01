//
//  ExplorerPaneUtilityButtonStyle.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerPaneUtilityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                isEnabled ? theme.textPrimary : theme.textTertiary
            )
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.imperialPrimer.opacity(0.64))
                    .offset(y: 3)

                RoundedRectangle(cornerRadius: 11)
                    .fill(theme.control)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(
                                theme.supportAccent.opacity(
                                    configuration.isPressed ? 0.38 : 0.2
                                )
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(0.26),
                radius: 2,
                x: 0,
                y: 3
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.18),
                radius: 6,
                x: 0,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
