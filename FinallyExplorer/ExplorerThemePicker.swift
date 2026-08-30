//
//  ExplorerThemePicker.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerThemePicker: View {
    @Environment(\.explorerTheme) private var theme

    let controller: ExplorerThemeController

    @State private var isPresented = false

    var body: some View {
        Button("Themes", systemImage: "paintpalette.fill") {
            isPresented = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerChromeIconButtonStyle())
        .help("Choose an app theme")
        .accessibilityIdentifier("theme-picker-button")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ExplorerThemePickerPopover(
                controller: controller,
                dismiss: dismissPopover
            )
            .environment(\.explorerTheme, controller.activeTheme)
        }
    }

    private func dismissPopover() {
        isPresented = false
    }
}

private struct ExplorerThemePickerPopover: View {
    @Environment(\.explorerTheme) private var theme

    let controller: ExplorerThemeController
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text("Hover to preview. Click to keep it.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            VStack(spacing: 6) {
                ForEach(ExplorerThemeChoice.allCases) { choice in
                    ExplorerThemePickerRow(
                        choice: choice,
                        isSelected: controller.selectedChoice == choice,
                        onHover: preview,
                        onSelect: select
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(theme.elevatedPanel)
        .onDisappear(perform: controller.endPreview)
    }

    private func preview(_ choice: ExplorerThemeChoice) {
        controller.preview(choice)
    }

    private func select(_ choice: ExplorerThemeChoice) {
        controller.select(choice)
        dismiss()
    }
}

private struct ExplorerThemePickerRow: View {
    @Environment(\.explorerTheme) private var activeTheme

    let choice: ExplorerThemeChoice
    let isSelected: Bool
    let onHover: (ExplorerThemeChoice) -> Void
    let onSelect: (ExplorerThemeChoice) -> Void

    private var previewTheme: ExplorerTheme {
        ExplorerTheme.palette(for: choice)
    }

    var body: some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Circle().fill(previewTheme.accent)
                    Circle().fill(previewTheme.supportAccent)
                    Circle().fill(previewTheme.warmHighlight)
                }
                .frame(width: 52, height: 22)

                Text(choice.title)
                    .font(ExplorerTheme.actionFont)
                    .foregroundStyle(activeTheme.textPrimary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(activeTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background(
                isSelected ? activeTheme.accentSoft : activeTheme.control,
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                onHover(choice)
            }
        }
        .accessibilityIdentifier("theme-choice-\(choice.rawValue)")
    }
}
