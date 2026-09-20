import SwiftUI

struct ExplorerPrivacySettingsView: View {
    @Environment(\.explorerTheme) private var theme
    @State private var selectedDocument: ExplorerLegalDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your files stay on your Mac", systemImage: "internaldrive")
                        .font(.headline)
                    Text("Search and AI run locally. No account required.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Documents")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(ExplorerLegalDocument.allCases) { document in
                        Button {
                            selectedDocument = document
                        } label: {
                            HStack {
                                Label(document.title, systemImage: document.systemImage)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(theme.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("settings-\(document.rawValue)-button")
                    }

                    Text("Available offline. Privacy & Terms are pre-release drafts.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Support")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 12) {
                        Text(ExplorerSupport.email)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        if let emailURL = ExplorerSupport.emailURL {
                            Link("Email Support", destination: emailURL)
                                .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                                .fixedSize()
                                .accessibilityIdentifier("settings-email-support-button")
                        }
                    }
                    Text("No files or diagnostics are sent automatically.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(18)
                .background(theme.control, in: .rect(cornerRadius: 14))
            }
            .font(.body)
            .padding(24)
        }
        .frame(width: 580)
        .frame(maxHeight: .infinity)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
        .sheet(item: $selectedDocument) { document in
            ExplorerLegalDocumentView(document: document)
        }
        .accessibilityIdentifier("privacy-settings-view")
    }
}
