//
//  NearbyDevicePickerView.swift
//  FinallyExplorer
//

import SwiftUI

struct NearbyDevicePickerView: View {
    @Environment(\.explorerTheme) private var theme

    let coordinator: NearbyTransferCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby Transfer")
                        .font(ExplorerTheme.paneTitleFont)
                    Text("Only devices on this local network can appear here.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Close", systemImage: "xmark") {
                    coordinator.presentation = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ExplorerToolbarButtonStyle())
            }

            if coordinator.pendingSourceURLs.isEmpty {
                Label(
                    "Nearby receiving is active. Select a file or folder to send.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(theme.supportAccent)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text(selectionSummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }

            Group {
                if let statusMessage = coordinator.statusMessage {
                    ContentUnavailableView(
                        "Local Network Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(statusMessage)
                    )
                } else if coordinator.peers.isEmpty {
                    ContentUnavailableView(
                        "Looking for Nearby Devices",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text(
                            "Open Nearby Transfer on the other Mac and keep both devices on the same network."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(coordinator.peers) { peer in
                                Button {
                                    coordinator.select(peer)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "laptopcomputer")
                                            .font(.title3)
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 32, height: 32)
                                        Text(peer.name)
                                            .font(ExplorerTheme.navigationFont)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(theme.textTertiary)
                                    }
                                    .padding(12)
                                    .background(
                                        theme.control,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    coordinator.pendingSourceURLs.isEmpty
                                        || coordinator.isPreparingTransfer
                                )
                                .accessibilityIdentifier(
                                    "nearby-peer-\(peer.id.uuidString.lowercased())"
                                )
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 210)

            HStack {
                Button("Stop Nearby Sharing") {
                    coordinator.stopSharing()
                }
                Spacer()
                Text("Files are encrypted end to end.")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(22)
        .frame(width: 520, height: 410)
        .background(theme.elevatedPanel)
        .foregroundStyle(theme.textPrimary)
        .accessibilityIdentifier("nearby-device-picker")
    }

    private var selectionSummary: String {
        let count = coordinator.pendingSourceURLs.count
        return count == 1 ? "Choose a Mac to send 1 item" : "Choose a Mac to send \(count) items"
    }
}
