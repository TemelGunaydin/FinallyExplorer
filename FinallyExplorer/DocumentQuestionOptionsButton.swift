import SwiftUI

struct DocumentQuestionOptionsButton: View {
    @Bindable var model: DocumentQuestionModel
    @State private var showsOptions = false

    var body: some View {
        Button("Document Options", systemImage: "slider.horizontal.3") { showsOptions.toggle() }
            .labelStyle(.iconOnly)
            .buttonStyle(ExplorerPaneUtilityButtonStyle(tint: .purple))
            .help("Reading limits and conversation options")
            .accessibilityIdentifier("document-options")
            .disabled(model.isWorking)
            .popover(isPresented: $showsOptions, arrowEdge: .top) {
                DocumentQuestionOptionsContent(model: model)
            }
    }
}
