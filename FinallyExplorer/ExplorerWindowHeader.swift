//
//  ExplorerWindowHeader.swift
//  FinallyExplorer
//

import SwiftUI

// CLEANMYMAC-INSPIRED WINDOW CHROME SPEC
// VISUAL HIERARCHY
// 1. Primary: the product name and folder mark, immediately after traffic lights.
// 2. Secondary: the current workspace location and pane count.
// 3. Tertiary: a subtle highlight and bottom hairline defining the content edge.
//
// SPATIAL GRID
// - Header height: 72pt; leading inset: 82pt to clear macOS traffic lights.
// - Brand gap: 11pt; right-side control gap: 8pt; outer trailing inset: 16pt.
// - Badge: 34pt with a continuous 10pt corner; status controls: 34pt high.
// - Content stays centered inside the expanded chrome so every control remains
//   below the macOS title-bar drag region and keeps its full hit target.
//
// TYPOGRAPHY AND EFFECTS
// - Brand: rounded title3 bold; subtitle/status: rounded caption/callout bold.
// - Full-bleed navy-to-aubergine gradient, 0.75pt bottom highlight.
struct ExplorerWindowHeader: View {
    let activeFolderTitle: String
    let paneCount: Int
    let isPreviewVisible: Bool
    let onToggleSidebar: () -> Void
    let onTogglePreview: () -> Void
    let onResetView: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.11))

                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ExplorerTheme.accent)
                        .offset(y: -0.5)
                }
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.75)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Finally Explorer")
                        .font(ExplorerTheme.brandFont)
                        .foregroundStyle(ExplorerTheme.chromeText)

                    Text("Your files. Your workspace.")
                        .font(.caption)
                        .foregroundStyle(ExplorerTheme.chromeSecondaryText)
                }
            }

            Button("Toggle Sidebar", systemImage: "sidebar.leading") {
                onToggleSidebar()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(ExplorerChromeButtonStyle())
            .padding(.leading, 14)
            .help("Show or hide the sidebar")

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                if paneCount == 1 {
                    Button(
                        isPreviewVisible ? "Hide Preview" : "Show Preview",
                        systemImage: "sidebar.trailing",
                        action: onTogglePreview
                    )
                    .buttonStyle(ExplorerChromeActionButtonStyle())
                    .help(
                        isPreviewVisible
                            ? "Hide the preview area"
                            : "Show the preview area"
                    )
                } else {
                    Button(
                        "Reset View",
                        systemImage: "rectangle",
                        action: onResetView
                    )
                    .buttonStyle(ExplorerChromeActionButtonStyle())
                    .help("Keep the active pane and close the other panes")
                }

                HStack(spacing: 8) {
                    Label(activeFolderTitle, systemImage: "folder.fill")
                        .lineLimit(1)
                        .frame(maxWidth: 240)

                    Label(
                        paneCount == 1 ? "1 pane" : "\(paneCount) panes",
                        systemImage: paneCount == 1
                            ? "rectangle"
                            : "rectangle.split.2x1"
                    )
                }
                .font(.system(.callout, design: .rounded).bold())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ExplorerTheme.chromeText)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                }
            }
        }
        .padding(.leading, 82)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(ExplorerTheme.windowChrome)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ExplorerTheme.chromeDivider)
                .frame(height: 0.75)
        }
    }
}
