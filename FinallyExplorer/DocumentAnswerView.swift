import SwiftUI

struct DocumentAnswerView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let turn = model.history.last {
                    Text("AI answer — check the supporting quotes. Citation matching confirms the quoted text exists, not that every interpretation is correct.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    DocumentAnswerTurnView(turn: turn) { model.inspectedClaim = $0 }
                } else if model.passages.isEmpty {
                    ContentUnavailableView("Ask About Your Documents", systemImage: "text.bubble",
                        description: Text("Read selected documents, then ask a specific question in English. Answers cite supporting text from those documents only."))
                        .frame(maxWidth: .infinity)
                }
                if model.passages.isEmpty == false {
                    DisclosureGroup("Retrieved passages (\(model.passages.count))") {
                        if let question = model.retrievedQuestion {
                            Text("Passages for: \(question)").font(.callout.weight(.semibold)).textSelection(.enabled)
                        }
                        if let resolved = model.resolvedQuestion, resolved != model.retrievedQuestion {
                            Text("Interpreted as: \(resolved)").font(.callout).textSelection(.enabled)
                        }
                        Text(model.usedSemanticSearch ? "Matched by meaning and keywords" : "Matched by keywords only")
                            .font(.caption).foregroundStyle(theme.textSecondary)
                        ForEach(model.passages) { passage in
                            VStack(alignment: .leading) {
                                Text(passage.sourceLabel).font(.headline)
                                Text(passage.text).font(.callout).textSelection(.enabled)
                            }.padding(.vertical, 8)
                        }
                    }
                }
                if model.history.count > 1 {
                    DisclosureGroup("Previous answers (\(model.history.count - 1))") {
                        ForEach(model.history.dropLast()) { turn in
                            DocumentAnswerTurnView(turn: turn) { model.inspectedClaim = $0 }
                                .padding(.vertical, 8)
                        }
                    }.accessibilityIdentifier("document-previous-answers")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
