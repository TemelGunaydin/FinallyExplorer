import SwiftUI

struct DocumentAnswerTurnView: View {
    @Environment(\.explorerTheme) private var theme
    let turn: DocumentQuestionTurn
    let onInspect: (DocumentAnswerClaim) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(turn.question).font(.headline).textSelection(.enabled)
            if turn.claims.contains(where: { $0.source.isOCR }) {
                Text("Includes OCR text. Verify names, dates and amounts against the original PDF page.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("document-answer-ocr-notice")
            }
            if turn.resolvedQuestion != turn.question {
                Text("Interpreted as: \(turn.resolvedQuestion)")
                    .font(.callout).foregroundStyle(theme.textSecondary).textSelection(.enabled)
                    .accessibilityIdentifier("document-resolved-question")
            }
            ForEach(turn.claims) { claim in
                VStack(alignment: .leading, spacing: 8) {
                    Text(claim.statement).textSelection(.enabled)
                        .accessibilityIdentifier("document-answer-claim")
                    Text("“\(claim.quote)”").font(.callout).textSelection(.enabled).foregroundStyle(theme.textSecondary)
                    Button(claim.source.sourceLabel, systemImage: "doc.text.magnifyingglass") { onInspect(claim) }
                        .buttonStyle(.plain).foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(theme.accentSoft, in: .rect(cornerRadius: 6))
                        .help("Inspect the supporting source excerpt")
                        .accessibilityIdentifier("document-citation-\(claim.source.id)")
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: .rect(cornerRadius: 10))
            }
        }
    }
}
