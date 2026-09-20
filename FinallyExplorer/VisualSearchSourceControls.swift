import SwiftUI

struct VisualSearchSourceControls: View {
    @Environment(\.explorerTheme) private var theme
    @Bindable var model: VisualSearchModel

    private var folderTitle: String {
        guard let url = model.sourceURL else { return "Choose Folder…" }
        return url.lastPathComponent.isEmpty ? "Startup Disk" : url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.chooseFolder) {
                HStack(spacing: 10) {
                    Image(systemName: "folder").accessibilityHidden(true)
                    Text(folderTitle)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityIdentifier("visual-search-source")
                    Image(systemName: "chevron.down").accessibilityHidden(true)
                }
            }
            .help(model.sourceURL?.path ?? "Choose a folder to analyze")
            .accessibilityLabel("Choose Folder")
            .accessibilityValue(model.sourceURL?.path ?? "No folder selected")
            .accessibilityIdentifier("visual-search-choose-folder")
            Spacer(minLength: 0)
            Button(model.snapshot == nil ? "Analyze Folder" : "Analyze Again", systemImage: "sparkle.magnifyingglass") {
                model.analyze()
            }
            .buttonStyle(ExplorerDialogButtonStyle(isProminent: true))
            .disabled(model.sourceURL == nil)
            .fixedSize()
            .accessibilityIdentifier("visual-search-analyze")
        }
        .padding(12)
        .background(theme.control, in: .rect(cornerRadius: 12))
        .disabled(model.isWorking)
    }
}
