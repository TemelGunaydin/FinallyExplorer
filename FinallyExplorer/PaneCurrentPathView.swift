//
//  PaneCurrentPathView.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneCurrentPathView: View {
    @Environment(\.explorerTheme) private var theme

    let directoryURL: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .frame(width: 24, height: 24)
                .background(
                    theme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .accessibilityHidden(true)

            Text("Current path")
                .font(.system(.callout, design: .rounded))
                .bold()
                .foregroundStyle(theme.textPrimary)
                .fixedSize()

            Text(directoryURL.path(percentEncoded: false))
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("pane-location-path")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            theme.control,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(theme.accent.opacity(0.2), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}
