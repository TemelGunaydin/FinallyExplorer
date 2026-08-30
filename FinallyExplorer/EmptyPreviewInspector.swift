//
//  EmptyPreviewInspector.swift
//  FinallyExplorer
//

import SwiftUI

// PREVIEW EMPTY-STATE SPEC
// - A persistent 64pt header prevents the inspector from reading as blank space.
// - The central 72pt icon surface echoes the rounded, dimensional reference cards.
// - Title and guidance use the same rounded hierarchy as navigation and actions.
struct EmptyPreviewInspector: View {
    @Environment(\.explorerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)

                Text("Preview")
                    .font(ExplorerTheme.paneTitleFont)
                    .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 64)
            .background(theme.elevatedPanel)

            Divider()
                .overlay(theme.divider)

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
        }
        .background(theme.inspector)
    }
}
