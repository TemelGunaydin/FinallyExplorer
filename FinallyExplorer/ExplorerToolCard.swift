import SwiftUI

struct ExplorerToolCard: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let tool: ExplorerTool
    var isFeatured = false
    let isHighlighted: Bool
    let onHighlight: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: tool.systemImage)
                    .font(.title2).foregroundStyle(theme.textPrimary)
                    .frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.title).font(.system(.headline, design: .rounded))
                    Text(tool.detail).font(.callout).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        }
        .buttonStyle(ExplorerDialogButtonStyle(isProminent: isFeatured, showsFocus: isHighlighted))
        .onHover { if $0 && isEnabled { onHighlight() } }
        .accessibilityLabel(tool.title).accessibilityHint(tool.detail)
        .accessibilityValue(isHighlighted ? "Selected" : "")
        .accessibilityIdentifier(tool.accessibilityID)
    }
}
