import SwiftUI

struct SmartSearchControls: View {
    @Environment(\.explorerTheme) private var theme
    let model: GlobalSearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Smart Search", systemImage: "sparkles")
                    .font(.headline)
                Spacer(minLength: 0)
                SettingsLink { Text("AI Settings") }
                    .buttonStyle(ExplorerDialogButtonStyle())
                    .accessibilityIdentifier("smart-search-settings-link")
                Button("Normal Search", action: useNormalSearch)
                    .buttonStyle(ExplorerDialogButtonStyle())
                    .accessibilityIdentifier("smart-search-normal-button")
                Button("Search", systemImage: "arrow.right", action: model.submitSmartSearch)
                    .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                    .disabled(model.hasQuery == false || model.isSearching)
                    .accessibilityIdentifier("smart-search-submit-button")
            }

            if let plan = model.smartSearchPlan {
                Text(plan.filterLabels().joined(separator: "  ·  "))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Interpreted search filters")
                    .accessibilityIdentifier("smart-search-filters")
                Text("\(model.results.count) results")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(12)
        .foregroundStyle(theme.textPrimary)
        .background(theme.elevatedPanel)
    }

    private func useNormalSearch() {
        model.usesSmartSearch = false
    }
}
