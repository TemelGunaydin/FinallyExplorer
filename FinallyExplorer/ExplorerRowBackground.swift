//
//  ExplorerRowBackground.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerRowBackground: View {
    @Environment(\.explorerTheme) private var theme

    let isSelected: Bool
    let isHidden: Bool

    var body: some View {
        if isSelected || isHidden {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? theme.selectedRow
                        : theme.warmHighlight.opacity(0.1)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isHidden
                                ? theme.warmHighlight.opacity(0.52)
                                : theme.accent.opacity(0.24),
                            style: StrokeStyle(
                                lineWidth: 0.75,
                                dash: isHidden ? [4, 3] : []
                            )
                        )
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        }
    }
}
