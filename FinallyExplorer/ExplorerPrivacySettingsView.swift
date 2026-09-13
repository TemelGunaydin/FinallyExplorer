import SwiftUI

struct ExplorerPrivacySettingsView: View {
    @Environment(\.explorerTheme) private var theme
    @State private var selectedDocument: ExplorerLegalDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Privacy & Support", systemImage: "hand.raised")
                    .font(.system(.title2, design: .rounded).weight(.semibold))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Your files stay on your Mac", systemImage: "internaldrive")
                        .font(ExplorerTheme.actionFont)
                    Text("File searches, image analysis, and AI requests are processed locally. No account or external AI API is required.")
                        .foregroundStyle(theme.textSecondary)
                    Text("Preferences and offline catalogs are saved locally. Clear document or photo analysis to forget its context; closing only the tool panel may retain it in this window.")
                        .foregroundStyle(theme.textSecondary)

                    Divider().overlay(theme.divider)

                    ForEach(ExplorerLegalDocument.allCases) { document in
                        Button(document.title, systemImage: document.systemImage) {
                            selectedDocument = document
                        }
                        .accessibilityIdentifier("settings-\(document.rawValue)-button")
                    }

                    Text("These documents are included in the app and can be read offline. Policy and terms are pre-release drafts pending publication review.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(18)
                .background(theme.control, in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Need a hand?", systemImage: "envelope")
                        .font(ExplorerTheme.actionFont)
                    Text("Include your app version, macOS version, and steps to reproduce the issue. Redact personal paths and sensitive information before attaching a screenshot.")
                        .foregroundStyle(theme.textSecondary)
                    if let emailURL = ExplorerSupport.emailURL {
                        Link("Email Support", destination: emailURL)
                            .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
                            .accessibilityIdentifier("settings-email-support-button")
                    }
                    Text(ExplorerSupport.email)
                        .textSelection(.enabled)
                    Text("Nothing is attached or sent automatically.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(18)
                .background(theme.control, in: .rect(cornerRadius: 14))
            }
            .font(.body)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
