import SwiftUI

struct VisualSearchOptionsButton: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel
    @State private var showsOptions = false

    var body: some View {
        Button("Analysis Options", systemImage: "slider.horizontal.3") {
            showsOptions.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerPaneUtilityButtonStyle())
        .help("Analysis options")
        .accessibilityValue(model.includesHidden ? "Hidden items included" : "Hidden items excluded")
        .accessibilityIdentifier("visual-search-options")
        .disabled(model.isWorking)
        .popover(isPresented: $showsOptions, arrowEdge: .top) {
            Toggle("Include hidden items", isOn: $model.includesHidden)
                .toggleStyle(.checkbox)
                .disabled(model.isWorking)
                .help("Changing this option clears the current analysis.")
                .accessibilityIdentifier("visual-search-hidden-items")
                .padding(18)
                .foregroundStyle(theme.textPrimary)
                .background(theme.panel)
                .tint(theme.accent)
        }
    }
}
