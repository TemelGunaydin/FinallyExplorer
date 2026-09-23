import SwiftUI

struct DocumentQuestionOptionsContent: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Formats & Reading Limits").font(.headline)
            Text("PDF, TXT, MD, JSON, CSV · Up to 5 files")
            Text("20 MB and 100 PDF pages per file. Up to 20 scanned pages with English OCR.")
                .foregroundStyle(theme.textSecondary)
            Text("Processed on this Mac. Clear to forget documents and answers.")
                .foregroundStyle(theme.textSecondary)
            if model.passages.isEmpty == false {
                DisclosureGroup("Source excerpts (\(model.passages.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.passages) { passage in
                                Text(passage.sourceLabel).font(.headline)
                                Text(passage.text).textSelection(.enabled)
                            }
                        }
                    }.frame(maxHeight: 200)
                }
                .help("Candidate excerpts, not verified answers. Answer citations are shown with each claim.")
            }
            if model.history.isEmpty == false {
                Divider()
                Button(
                    "New Conversation", systemImage: "bubble.left.and.text.bubble.right", action: model.newConversation
                )
                .accessibilityIdentifier("document-new-conversation")
                .help("Keep the documents ready and forget previous questions")
            }
            if model.selection.isEmpty == false {
                Button("Clear Documents & Answers", systemImage: "eraser", action: model.clear)
                    .accessibilityIdentifier("document-clear")
            }
        }
        .font(.callout).padding(18).frame(width: 350)
        .foregroundStyle(theme.textPrimary).background(theme.panel).tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
    }
}
