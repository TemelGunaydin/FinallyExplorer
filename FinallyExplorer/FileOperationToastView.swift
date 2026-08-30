//
//  FileOperationToastView.swift
//  FinallyExplorer
//

import SwiftUI

struct FileOperationToastView: View {
    @Environment(\.explorerTheme) private var theme

    let notice: FileOperationNotice

    var body: some View {
        Label(notice.message, systemImage: notice.systemImage)
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(theme.elevatedPanel, in: .capsule)
            .overlay {
                Capsule()
                    .stroke(theme.accent.opacity(0.48), lineWidth: 1)
            }
            .shadow(
                color: theme.imperialPrimer.opacity(0.28),
                radius: 12,
                x: 0,
                y: 5
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(notice.message)
            .accessibilityValue(notice.message)
            .accessibilityIdentifier("file-operation-toast")
    }
}
