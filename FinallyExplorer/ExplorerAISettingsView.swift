import SwiftUI

struct ExplorerAISettingsView: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var settings: ExplorerAISettings

    @State private var refreshGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionTitle("Features")
                VStack(spacing: 16) {
                    featureRow(
                        "Ask AI", description: "Find files in English and refine with follow-up questions.",
                        isOn: $settings.isSmartSearchEnabled, identifier: "ai-settings-smart-search-toggle"
                    )
                    Divider().overlay(theme.divider)
                    featureRow(
                        "Document Questions", description: "Ask about selected documents. Answers include sources.",
                        isOn: $settings.isDocumentQuestionsEnabled, identifier: "ai-settings-document-questions-toggle"
                    )
                    Divider().overlay(theme.divider)
                    featureRow(
                        "Smart Rename", description: "Suggest a name. You review it before renaming.",
                        isOn: $settings.isSmartRenameEnabled, identifier: "ai-settings-enabled-toggle"
                    )
                    Divider().overlay(theme.divider)
                    featureRow(
                        "Use contents for renaming", description: "Include a short excerpt by default. Change this for each suggestion.",
                        isOn: $settings.usesFileContentsByDefault, identifier: "ai-settings-contents-toggle",
                        isEnabled: settings.isSmartRenameEnabled
                    )
                }
                .toggleStyle(.switch)
                .padding(18)
                .background(theme.control, in: .rect(cornerRadius: 14))

                sectionTitle("Apple Intelligence")
                VStack(alignment: .leading, spacing: 12) {
                    Label(statusMessage, systemImage: statusSymbol)
                        .font(.callout)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ai-settings-model-status")

                    Text("Runs on this Mac. No API key or extra download.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button("System Settings", systemImage: "gearshape") {
                            SystemPrivacySettingsOpener.openAppleIntelligence()
                        }
                        .help("Open Apple Intelligence settings")
                        .accessibilityIdentifier("ai-settings-system-button")
                        Spacer()
                        Button("Check Again") { refreshGeneration += 1 }
                            .disabled(settings.isCheckingAvailability)
                            .accessibilityIdentifier("ai-settings-refresh-button")
                    }
                }
                .padding(18)
                .background(theme.control, in: .rect(cornerRadius: 14))

                ExplorerReadingDetails(title: "Privacy & how it works", text: "Ask AI uses Spotlight to find files; file contents are not sent to the search model. Photo analysis requires your approval. Document Questions and Smart Rename read only the content you choose, on this Mac. Turning off Document Questions cancels work and clears its document context.")
            }
            .padding(24)
        }
        .frame(width: 580)
        .frame(maxHeight: .infinity)
        .foregroundStyle(theme.textPrimary)
        .background(theme.panel)
        .tint(theme.accent)
        .buttonStyle(ExplorerDialogButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-settings-view")
        .task(id: refreshGeneration) { await settings.refreshAvailability() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { refreshGeneration += 1 }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 4)
    }

    private func featureRow(
        _ title: String, description: String, isOn: Binding<Bool>, identifier: String,
        isEnabled: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(theme.textPrimary)
                Text(description).font(.callout).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(isEnabled == false)
                .accessibilityLabel(title)
                .accessibilityHint(description)
                .accessibilityIdentifier(identifier)
        }
    }

    private var statusMessage: String {
        guard let availability = settings.availability else {
            return "Checking model availability…"
        }
        return availability == .available
            ? "Ready to use"
            : OnDeviceModelError.unavailable(availability).localizedDescription
    }

    private var statusSymbol: String {
        settings.availability == .available ? "checkmark.circle.fill" : "info.circle.fill"
    }
}
