import SwiftUI

struct DocumentCitationSheet: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let claim: DocumentAnswerClaim
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(claim.source.sourceLabel).font(.headline).lineLimit(2)
                .accessibilityIdentifier("document-source-sheet")
            Text("Source excerpt from the document snapshot").font(.callout).foregroundStyle(theme.textSecondary)
            ScrollView { Text(claim.source.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Show in Explorer", systemImage: "arrow.up.forward.app") { dismiss(); onReveal() }
                    .accessibilityIdentifier("document-source-reveal")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("document-source-done")
            }
        }
        .padding(22).frame(width: 600, height: 380)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
    }
}
