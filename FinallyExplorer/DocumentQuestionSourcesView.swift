import SwiftUI

struct DocumentQuestionSourcesView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose Documents…", action: model.chooseDocuments).accessibilityIdentifier("document-choose")
                Spacer()
                Button("Read Documents", systemImage: "doc.text.magnifyingglass") { model.readDocuments() }
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled((1...5).contains(model.selection.count) == false).accessibilityIdentifier("document-read")
            }
            if model.selection.isEmpty {
                Text("Select up to 5 PDF, TXT, MD, JSON or CSV files. No text is read until you select Read Documents.")
            } else {
                ForEach(model.selection.prefix(5), id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc.text").lineLimit(1).truncationMode(.middle)
                }
                if model.selection.count > 5 {
                    Text("\(model.selection.count - 5) more selected. Choose at most 5 documents to continue.")
                }
            }
            Text("Local files only · 20 MB and 100 PDF pages per file · Image-only PDFs are not supported")
                .font(.caption).foregroundStyle(theme.textSecondary)
            if model.documents.isEmpty == false {
                Text("\(model.documents.count) documents ready · \(model.documents.reduce(0) { $0 + $1.skippedPageCount }) PDF pages without readable text skipped")
                    .font(.caption).accessibilityIdentifier("document-ready")
                Text(model.retrievalIndex?.supportsSemanticSearch == true
                     ? "Local search: meaning + keywords · English"
                     : "Keywords only: the local English meaning model is unavailable.")
                    .font(.caption).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("document-search-mode")
            }
        }
        .font(.callout).padding(12).background(theme.control, in: .rect(cornerRadius: 12))
        .disabled(model.isWorking || model.isEnabled == false)
    }
}
