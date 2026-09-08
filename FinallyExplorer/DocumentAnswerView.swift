import SwiftUI

struct DocumentAnswerView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let question = model.answeredQuestion {
                    Text(question).font(.headline).textSelection(.enabled)
                    Text("AI answer — check the supporting quotes. Citation matching confirms the quoted text exists, not that every interpretation is correct.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    ForEach(model.claims) { claim in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(claim.statement).textSelection(.enabled)
                                .accessibilityIdentifier("document-answer-claim")
                            Text("“\(claim.quote)”").font(.callout).textSelection(.enabled).foregroundStyle(theme.textSecondary)
                            Button(claim.source.sourceLabel, systemImage: "doc.text.magnifyingglass") { model.inspectedClaim = claim }
                                .buttonStyle(.plain).foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(theme.accentSoft, in: .rect(cornerRadius: 6))
                                .help("Inspect the supporting source excerpt")
                                .accessibilityIdentifier("document-citation-\(claim.source.id)")
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.control, in: .rect(cornerRadius: 10))
                    }
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
                        ForEach(model.passages) { passage in
                            VStack(alignment: .leading) {
                                Text(passage.sourceLabel).font(.headline)
                                Text(passage.text).font(.callout).textSelection(.enabled)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
