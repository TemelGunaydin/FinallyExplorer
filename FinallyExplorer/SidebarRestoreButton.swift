//
//  SidebarRestoreButton.swift
//  FinallyExplorer
//

import SwiftUI

struct SidebarRestoreButton: View {
    let hiddenPlaces: [SidebarBuiltInPlace]
    let onRestore: (SidebarBuiltInPlace) -> Void
    let onRestoreAll: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button(
            "Restore Sidebar Items",
            systemImage: "arrow.counterclockwise",
            action: present
        )
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerSidebarActionButtonStyle())
        .frame(width: 42)
        .help("Restore items removed from the sidebar")
        .accessibilityIdentifier("sidebar-restore-items-button")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SidebarRestorePopover(
                hiddenPlaces: hiddenPlaces,
                onRestore: restore,
                onRestoreAll: restoreAll
            )
        }
    }

    private func present() {
        isPresented = true
    }

    private func restore(_ place: SidebarBuiltInPlace) {
        isPresented = false
        onRestore(place)
    }

    private func restoreAll() {
        isPresented = false
        onRestoreAll()
    }
}
