import SwiftUI

struct DocumentSourceButton: View {
    @Environment(\.explorerTheme) private var theme
    let passage: DocumentPassage
    let onInspect: () -> Void

    var body: some View {
        Button(action: onInspect) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(passage.fileName).lineLimit(1).truncationMode(.middle)
                    Text((passage.page.map { "Page \($0)" } ?? "Text excerpt") + (passage.isOCR ? " · OCR" : ""))
                        .font(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ExplorerDialogButtonStyle())
        .accessibilityLabel(passage.sourceLabel)
        .accessibilityHint("Inspect the supporting source excerpt")
        .accessibilityIdentifier("document-citation-\(passage.id)")
    }
}
