//
//  PaneLocationMenu.swift
//  FinallyExplorer
//

import SwiftUI

struct PaneLocationMenu: View {
    let selectedPlace: SidebarPlace
    let places: [SidebarPlace]
    let isCompact: Bool
    let onSelect: (SidebarPlace) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        Button(action: presentPicker) {
            HStack(spacing: 9) {
                Image(systemName: selectedPlace.systemImage)
                    .symbolRenderingMode(.hierarchical)

                Text(selectedPlace.title)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, isCompact ? 11 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(PaneLocationButtonStyle(isCompact: isCompact))
        .accessibilityLabel("Current location: \(selectedPlace.title)")
        .accessibilityHint("Choose a folder for this pane")
        .accessibilityIdentifier("pane-location-menu")
        .popover(isPresented: $isPickerPresented, arrowEdge: .top) {
            PaneLocationPickerPopover(
                selectedPlace: selectedPlace,
                places: places,
                onSelect: select
            )
        }
    }

    private func presentPicker() {
        isPickerPresented = true
    }

    private func select(_ place: SidebarPlace) {
        isPickerPresented = false
        onSelect(place)
    }
}
