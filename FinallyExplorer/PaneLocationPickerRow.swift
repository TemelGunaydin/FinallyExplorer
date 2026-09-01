//
//  PaneLocationPickerRow.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneLocationPickerRow: View {
    @Environment(\.explorerTheme) private var theme

    let place: SidebarPlace
    let isSelected: Bool
    let onSelect: (SidebarPlace) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: place.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        isSelected ? theme.accent : theme.textSecondary
                    )
                    .frame(width: 22)

                Text(place.title)
                    .font(ExplorerTheme.actionFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(.rect)
            .background(
                isSelected || isHovered ? theme.accentSoft : theme.control,
                in: .rect(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                            ? theme.accent.opacity(0.5)
                            : theme.divider.opacity(0.7),
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(place.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pane-location-option-\(place.title)")
    }

    private func select() {
        onSelect(place)
    }
}
