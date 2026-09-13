import SwiftUI

struct ExplorerAISettingsView: View {
    @Environment(\.explorerTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var settings: ExplorerAISettings

    @State private var refreshGeneration = 0

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Label("On-Device AI", systemImage: "sparkles")
                .font(.system(.title2, design: .rounded).weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable Ask AI & Smart Search", isOn: $settings.isSmartSearchEnabled)
                    .accessibilityIdentifier("ai-settings-smart-search-toggle")
                Text("Describe files in English, then refine with follow-up questions. Apple Intelligence interprets your request; Spotlight finds the files. Search sends no file contents to the model.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)

                Text("Photo searches open Visual Search. Folder analysis requires your approval.")
                    .font(.callout).foregroundStyle(theme.textSecondary)

                Divider().overlay(theme.divider)
                Toggle("Enable Document Questions", isOn: $settings.isDocumentQuestionsEnabled)
                    .accessibilityIdentifier("ai-settings-document-questions-toggle")
                Text("Read selected files and scanned PDFs, then ask for source-cited answers. Turning this off cancels work and forgets the document context.")
                    .font(.callout).foregroundStyle(theme.textSecondary)

                Divider().overlay(theme.divider)

                Toggle("Enable Smart Rename", isOn: $settings.isSmartRenameEnabled)
                    .accessibilityIdentifier("ai-settings-enabled-toggle")
                Text("Suggest a name when you ask, then review it before renaming. Your files stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)

                Divider().overlay(theme.divider)

                Toggle(
                    "Use file contents for Smart Rename by default",
                    isOn: $settings.usesFileContentsByDefault
                )
                .disabled(settings.isSmartRenameEnabled == false)
                .accessibilityIdentifier("ai-settings-contents-toggle")
                Text("Use a short excerpt from supported text, PDFs, or images. You can change this for each suggestion.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            .toggleStyle(.switch)
            .padding(18)
            .background(theme.control, in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Apple Intelligence", systemImage: "desktopcomputer")
                        .font(ExplorerTheme.actionFont)
                    Spacer()
                    Text("ON-DEVICE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                }

                Label(statusMessage, systemImage: statusSymbol)
                    .font(.callout)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai-settings-model-status")

                Text("macOS manages the model. No API key or separate download is needed.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Open Apple Intelligence Settings", systemImage: "gearshape") {
                        SystemPrivacySettingsOpener.openAppleIntelligence()
                    }
                    .accessibilityIdentifier("ai-settings-system-button")
                    Spacer()
                    Button("Check Again") { refreshGeneration += 1 }
                        .disabled(settings.isCheckingAvailability)
                        .accessibilityIdentifier("ai-settings-refresh-button")
                }
            }
            .padding(18)
            .background(theme.control, in: .rect(cornerRadius: 14))
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

    private var statusMessage: String {
        guard let availability = settings.availability else {
            return "Checking model availability…"
        }
        return availability == .available
            ? "Ready for search, photo descriptions, document answers, and name suggestions."
            : OnDeviceModelError.unavailable(availability).localizedDescription
    }

    private var statusSymbol: String {
        settings.availability == .available ? "checkmark.circle.fill" : "info.circle.fill"
    }
}
