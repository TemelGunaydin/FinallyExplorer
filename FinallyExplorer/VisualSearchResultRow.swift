import AppKit
import SwiftUI

struct VisualSearchResultRow: View {
    @Environment(\.explorerTheme) private var theme
    @State private var thumbnail: NSImage?
    let match: VisualSearchMatch
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(theme.textSecondary) }
            }
            .frame(width: 110, height: 84)
            .background(theme.control, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(URL(filePath: match.entry.relativePath).lastPathComponent)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(match.entry.relativePath).font(.caption).foregroundStyle(theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                if let capture = match.entry.evidence.captureDate {
                    Text("Captured: \(capture.date.formatted(date: .abbreviated, time: .shortened))\(capture.assumedLocalTimeZone ? " · time zone assumed" : "")")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
                if match.labels.isEmpty == false {
                    Text("Visual labels: " + match.labels.joined(separator: ", "))
                        .font(.callout).lineLimit(3).textSelection(.enabled)
                }
                if let excerpt = match.excerpt {
                    Text("Text in image: “\(excerpt)”").font(.callout).lineLimit(4).textSelection(.enabled)
                }
                if match.entry.evidence.textWasTruncated {
                    Text("Only the first 4,000 text characters were indexed.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show in Explorer", systemImage: "arrow.up.forward.app", action: onReveal)
                .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle())
                .help("Show \(match.entry.relativePath) in Explorer")
                .accessibilityLabel("Show \(match.entry.relativePath) in Explorer")
                .accessibilityIdentifier("visual-search-reveal-\(match.entry.relativePath)")
        }
        .padding(12).background(theme.control.opacity(0.55), in: .rect(cornerRadius: 12))
        .task(id: match.entry.evidence.thumbnail) { thumbnail = NSImage(data: match.entry.evidence.thumbnail) }
        .accessibilityElement(children: .contain)
    }
}
