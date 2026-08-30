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
        .buttonStyle(ExplorerToolbarButtonStyle())
        .help(
            sourceURLs.isEmpty
                ? "Enable nearby receiving"
                : "Send the selection to a nearby Mac"
        )
        .accessibilityIdentifier("nearby-transfer-toolbar-button")
    }
}
