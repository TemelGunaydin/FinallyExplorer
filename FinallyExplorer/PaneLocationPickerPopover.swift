//
//  PaneLocationPickerPopover.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneLocationPickerPopover: View {
    @Environment(\.explorerTheme) private var theme

    let selectedPlace: SidebarPlace
    let places: [SidebarPlace]
    let onSelect: (SidebarPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Locations", systemImage: "folder.fill")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.textPrimary)

            Text("Choose the folder shown in this pane.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(places) { place in
                        PaneLocationPickerRow(
                            place: place,
                            isSelected: selectedPlace == place,
                            onSelect: onSelect
                        )
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(14)
        .frame(width: 286, height: pickerHeight)
        .background(theme.elevatedPanel)
        .presentationBackground(theme.elevatedPanel)
    }

    private var pickerHeight: CGFloat {
        min(430, 88 + (CGFloat(places.count) * 44))
    }
}
