import SwiftUI

struct ExplorerLegalDocumentView: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    private let document: ExplorerLegalDocument
    private let blocks: [ExplorerLegalBlock]?

    init(document: ExplorerLegalDocument) {
        self.document = document
        // Read only the small bundled document, once per presentation. No network or user-file access.
        blocks = (try? document.loadText()).map(ExplorerLegalBlock.parse)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(document.title, systemImage: document.systemImage)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("legal-document-done")
            }
            .padding(24)

            Divider().overlay(theme.divider)

            if let blocks {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(blocks) { block in
                            if block.isHeading {
                                Text(block.text)
                                    .font(.headline)
                                    .padding(.top, 8)
                                    .accessibilityAddTraits(.isHeader)
                            } else {
                                Text(.init(block.text))
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(24)
                }
            } else {
                ContentUnavailableView("Document Unavailable", systemImage: "doc.badge.ellipsis",
                    description: Text("This copy of the app is missing the document. Please contact \(ExplorerSupport.email)."))
            }
        }
        .frame(width: 640, height: 640)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .accessibilityIdentifier("legal-document-\(document.rawValue)")
    }

    private func close() { dismiss() }
}
