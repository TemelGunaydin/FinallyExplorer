//
//  NearbyTransferToolbarButton.swift
//  FinallyExplorer
//

import SwiftUI

struct NearbyTransferToolbarButton: View {
    @Environment(NearbyTransferCoordinator.self) private var nearbyTransfers

    let sourceURLs: [URL]

    var body: some View {
        Button("Nearby Transfer", systemImage: "person.2.wave.2") {
            nearbyTransfers.prepareToSend(sourceURLs)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExplorerPaneUtilityButtonStyle())
        .explorerTooltip(
            sourceURLs.isEmpty
                ? "Turn on nearby sharing"
                : "Send selected items nearby"
        )
        .accessibilityIdentifier("nearby-transfer-toolbar-button")
    }
}
