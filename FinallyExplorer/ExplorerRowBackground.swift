//
//  ExplorerRowBackground.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerRowBackground: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExplorerTheme.selectedRow)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            ExplorerTheme.accent.opacity(0.24),
                            lineWidth: 0.75
                        )
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        }
    }
}
