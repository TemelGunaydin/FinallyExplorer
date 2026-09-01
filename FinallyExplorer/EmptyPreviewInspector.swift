//
//  EmptyPreviewInspector.swift
//  FinallyExplorer
//

import SwiftUI

struct EmptyPreviewInspector: View {
    @Environment(\.explorerTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.accentSoft)

                Image(systemName: "eye.slash.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 72, height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        theme.accent.opacity(0.16),
                        lineWidth: 0.75
                    )
            }
            .accessibilityHidden(true)

            Text("Nothing to Preview")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text("Select a file or folder to see it here.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.inspector)
    }
}
