//
//  MountedVolumeSidebarRow.swift
//  FinallyExplorer
//

import SwiftUI

/// Keeps opening a mounted disk and ejecting it as independent pointer targets.
struct MountedVolumeSidebarRow: View {
    @Environment(\.explorerTheme) private var theme

    let volume: MountedVolume
    let isEjecting: Bool
    let onOpen: () -> Void
    let onEject: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                Label(volume.title, systemImage: "externaldrive")
                    .font(ExplorerTheme.sidebarNavigationFont)
                    .labelStyle(ExplorerSidebarLabelStyle())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(Self.rowIdentifier(for: volume.url))

            if volume.isEjectable {
                ejectControl
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contextMenu {
            if volume.isEjectable {
                Button(
                    "Eject “\(volume.title)”",
                    systemImage: "eject",
                    action: onEject
                )
                .disabled(isEjecting)
            }
        }
    }

    @ViewBuilder
    private var ejectControl: some View {
        if isEjecting {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
                .frame(width: 26, height: 28)
                .accessibilityLabel("Ejecting \(volume.title)")
                .accessibilityIdentifier(Self.progressIdentifier(for: volume.url))
        } else {
            Button(
                "Eject \(volume.title)",
                systemImage: "eject",
                action: onEject
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.chromeSecondaryText)
            .frame(width: 26, height: 28)
            .contentShape(Rectangle())
            .help("Eject \(volume.title)")
            .accessibilityIdentifier(Self.ejectIdentifier(for: volume.url))
        }
    }

    nonisolated static func rowIdentifier(for url: URL) -> String {
        "sidebar-location-\(url.standardizedFileURL.path(percentEncoded: false))"
    }

    nonisolated static func ejectIdentifier(for url: URL) -> String {
        "sidebar-eject-\(url.standardizedFileURL.path(percentEncoded: false))"
    }

    nonisolated static func progressIdentifier(for url: URL) -> String {
        "sidebar-eject-progress-\(url.standardizedFileURL.path(percentEncoded: false))"
    }
}
