import SwiftUI

struct ExplorerToolsPopover: View {
    @Environment(\.explorerTheme) private var theme
    @State private var highlightedTool: ExplorerTool = .visualSearch
    let hasFolder: Bool
    let onSelect: (ExplorerTool) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Tools", systemImage: "square.grid.2x2.fill")
                        .font(.system(.title2, design: .rounded).bold())
                    Text("More ways to work with your files.")
                        .font(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Close Tools", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly).buttonStyle(ExplorerPaneUtilityButtonStyle(isClose: true))
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("file-tools-close")
            }
            Text("FIND & UNDERSTAND").font(.caption.bold()).foregroundStyle(theme.textSecondary)
            VStack(spacing: 10) {
                ForEach([ExplorerTool.visualSearch, .documents]) { tool in
                    ExplorerToolCard(tool: tool, isFeatured: true, isHighlighted: highlightedTool == tool,
                        onHighlight: { highlightedTool = tool }) { onSelect(tool) }
                }
            }
            Text("ORGANIZE & MANAGE").font(.caption.bold()).foregroundStyle(theme.textSecondary)
            VStack(spacing: 10) {
                ForEach([ExplorerTool.duplicates, .organize, .offlineCatalogs]) { tool in
                    ExplorerToolCard(tool: tool, isHighlighted: highlightedTool == tool,
                        onHighlight: { highlightedTool = tool }) { onSelect(tool) }
                        .disabled(tool.requiresFolder && hasFolder == false)
                }
            }
            Label("On this Mac · You choose what to analyze or change", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(20).frame(width: 430)
        .foregroundStyle(theme.textPrimary).background(theme.panel)
        .accessibilityElement(children: .contain).accessibilityIdentifier("file-tools-popover")
        .onAppear { highlightedTool = .visualSearch }
        .background {
            ExplorerToolsKeyboardHandler(onMove: moveFocus,
                onActivate: { onSelect(highlightedTool) }, onClose: onClose)
                .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func moveFocus(_ offset: Int) {
        let tools = ExplorerTool.allCases.filter { hasFolder || $0.requiresFolder == false }
        guard let index = tools.firstIndex(of: highlightedTool) else { highlightedTool = .visualSearch; return }
        highlightedTool = tools[(index + offset + tools.count) % tools.count]
    }
}
