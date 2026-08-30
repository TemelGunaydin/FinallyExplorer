//
//  NearbyIncomingOfferView.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

struct NearbyIncomingOfferView: View {
    @Environment(\.explorerTheme) private var theme

    let offer: NearbyIncomingOffer
    let coordinator: NearbyTransferCoordinator
    @State private var destinationURL: URL

    init(
        offer: NearbyIncomingOffer,
        defaultDestinationURL: URL,
        coordinator: NearbyTransferCoordinator
    ) {
        self.offer = offer
        self.coordinator = coordinator
        _destinationURL = State(initialValue: defaultDestinationURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Incoming from \(offer.peerName)", systemImage: "arrow.down.circle.fill")
                .font(ExplorerTheme.paneTitleFont)
                .foregroundStyle(theme.accent)

            Text(offerSummary)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)

            if offer.itemNames.isEmpty == false {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(offer.itemNames, id: \.self) { name in
                        Label(name, systemImage: "doc")
                            .lineLimit(1)
                    }
                    if offer.itemCount > offer.itemNames.count {
                        Text("and \(offer.itemCount - offer.itemNames.count) more…")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Save to")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(theme.folderIcon)
                    Text(destinationURL.path(percentEncoded: false))
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("nearby-destination-path")
                    Spacer()
                    Button("Choose…", action: chooseDestination)
                        .accessibilityIdentifier("nearby-choose-destination-button")
                }
            }

            HStack {
                Button("Decline", role: .destructive) {
                    coordinator.decline(offer)
                }
                .accessibilityIdentifier("nearby-decline-button")
                Spacer()
                Button("Accept") {
                    coordinator.accept(offer, into: destinationURL)
                }
                .buttonStyle(ExplorerActionButtonStyle())
                .accessibilityIdentifier("nearby-accept-button")
            }
        }
        .padding(24)
        .frame(width: 540, height: 430)
        .background(theme.elevatedPanel)
        .foregroundStyle(theme.textPrimary)
        .accessibilityIdentifier("nearby-incoming-offer-sheet")
    }

    private var offerSummary: String {
        let itemText = offer.itemCount == 1 ? "1 item" : "\(offer.itemCount) items"
        return "\(itemText) • \(ByteCountFormatter.string(fromByteCount: Int64(clamping: offer.totalByteCount), countStyle: .file))"
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for Nearby Files"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        destinationURL = selectedURL.standardizedFileURL
    }
}
