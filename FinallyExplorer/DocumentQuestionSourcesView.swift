import SwiftUI

struct DocumentQuestionSourcesView: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: DocumentQuestionModel

    private var ocrPageCount: Int { model.documents.reduce(0) { $0 + $1.ocrPageCount } }
    private var skippedPageCount: Int { model.documents.reduce(0) { $0 + $1.skippedPageCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose Documents…", systemImage: "doc.badge.plus", action: model.chooseDocuments).accessibilityIdentifier("document-choose")
                Spacer()
                Button("Read Documents", systemImage: "doc.text.magnifyingglass") { model.readDocuments() }
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                    .disabled((1...5).contains(model.selection.count) == false).accessibilityIdentifier("document-read")
            }
            if model.selection.isEmpty == false {
                ForEach(model.selection.prefix(5), id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc.text").lineLimit(1).truncationMode(.middle)
                }
                if model.selection.count > 5 {
                    Text("\(model.selection.count - 5) more selected. Choose at most 5 documents to continue.")
                }
            }
            if model.documents.isEmpty == false {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").accessibilityHidden(true)
                    Text("\(model.documents.count) \(model.documents.count == 1 ? "document" : "documents") ready")
                        .accessibilityIdentifier("document-ready")
                }.font(.callout)
                if skippedPageCount > 0 {
                    Text("\(skippedPageCount) PDF pages skipped: no readable text.").foregroundStyle(theme.textSecondary)
                }
                if ocrPageCount > 0 {
                    Label("\(ocrPageCount) OCR \(ocrPageCount == 1 ? "page" : "pages") · Check originals for recognition errors", systemImage: "text.viewfinder")
                        .font(.callout).foregroundStyle(theme.textSecondary)
                        .accessibilityIdentifier("document-ocr-summary")
                }
            }
        }
        .font(.callout).padding(12).background(theme.control, in: .rect(cornerRadius: 12))
        .buttonStyle(ExplorerDialogButtonStyle())
        .disabled(model.isWorking || model.isEnabled == false)
    }
}
