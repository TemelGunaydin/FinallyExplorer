import SwiftUI

struct DocumentAnswerTurnView: View {
    @Environment(\.explorerTheme) private var theme
    let turn: DocumentQuestionTurn
    let onInspect: (DocumentAnswerClaim) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(turn.question).font(.headline).textSelection(.enabled)
            if turn.claims.contains(where: { $0.source.isOCR }) {
                Label("OCR source · Check names, dates and amounts in the original PDF.", systemImage: "text.viewfinder")
                    .font(.callout).foregroundStyle(theme.textSecondary)
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
                    DocumentSourceButton(passage: claim.source) { onInspect(claim) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: .rect(cornerRadius: 10))
            }
        }
    }
}
