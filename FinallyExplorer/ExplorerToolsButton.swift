import SwiftUI

struct ExplorerToolsButton: View {
    @State private var isPresented = false
    let hasFolder: Bool
    let onSelect: (ExplorerTool) -> Void

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2.fill")
                Text("Tools")
                Image(systemName: "chevron.down").font(.caption.bold()).accessibilityHidden(true)
            }
        }
        .buttonStyle(ExplorerDialogButtonStyle())
        .help("Visual Search, Ask Documents and file management tools")
        .accessibilityLabel("File Tools")
        .accessibilityIdentifier("window-file-tools-button")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ExplorerToolsPopover(hasFolder: hasFolder, onSelect: select, onClose: { isPresented = false })
        }
    }

    private func select(_ tool: ExplorerTool) {
        isPresented = false
        onSelect(tool)
    }
}
