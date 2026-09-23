import SwiftUI

struct VisualSearchOptionsButton: View {
    @Bindable var model: VisualSearchModel
    @State private var showsOptions = false

    var body: some View {
        Button("Search Options", systemImage: "slider.horizontal.3") {
            showsOptions.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerPaneUtilityButtonStyle(tint: .cyan))
        .help("Search options and analysis details")
        .accessibilityValue(model.includesHidden ? "Hidden items included" : "Hidden items excluded")
        .accessibilityIdentifier("visual-search-options")
        .disabled(model.isWorking)
        .popover(isPresented: $showsOptions, arrowEdge: .top) {
            VisualSearchOptionsContent(model: model)
        }
    }
}
