import SwiftUI

struct AskAISearchResultRow: View {
    @Environment(\.explorerTheme) private var theme
    let result: ExplorerSearchResult
    let onReveal: () -> Void

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 12) {
                FileItemIconView(item: result.item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.item.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(result.relativePath)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let capture = result.captureDate {
                        Text("Captured \(capture.date.formatted(date: .abbreviated, time: .shortened)) · EXIF\(capture.assumedLocalTimeZone ? " · local time zone assumed" : "")")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(theme.control.opacity(0.55), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Reveal \(result.item.name) in Finally Explorer")
        .accessibilityIdentifier("ask-ai-result-\(result.id)")
    }
}
