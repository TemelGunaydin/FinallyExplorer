//
//  ExplorerContextMenuRowModifier.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerContextMenuRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    let isDestructive: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .font(.callout)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                isDestructive ? Color.red : theme.textPrimary
            )
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 9)
            .contentShape(.rect(cornerRadius: 8))
            .background(
                isHovered && isEnabled
                    ? theme.accentSoft
                    : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: isHovered
            )
    }
}

extension View {
    func explorerContextMenuRow(isDestructive: Bool = false) -> some View {
        modifier(
            ExplorerContextMenuRowModifier(
                isDestructive: isDestructive
            )
        )
    }
}
