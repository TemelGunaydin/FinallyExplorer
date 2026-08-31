//
//  MountedVolumeMonitor.swift
//  FinallyExplorer
//

import AppKit
import Observation

nonisolated struct MountedVolumeEjectFailure: Identifiable, Equatable, Sendable {
    let volume: MountedVolume
    let message: String

    var id: URL { volume.url.standardizedFileURL }
}

/// Keeps the Locations section synchronized with macOS mount changes.
@MainActor
@Observable
final class MountedVolumeMonitor {
    private(set) var volumes: [MountedVolume] = []
    private(set) var ejectingVolumeURLs: Set<URL> = []
    private(set) var ejectFailure: MountedVolumeEjectFailure?

    @ObservationIgnored private let loadVolumes: @MainActor () -> [MountedVolume]
    @ObservationIgnored private let ejector: any MountedVolumeEjecting
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []

    init(
        loadVolumes: @escaping @MainActor () -> [MountedVolume] = {
            MountedVolume.discover()
        },
        ejector: any MountedVolumeEjecting = SystemMountedVolumeEjector(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        observesWorkspaceChanges: Bool = true
    ) {
        self.loadVolumes = loadVolumes
        self.ejector = ejector
        self.notificationCenter = notificationCenter
        refresh()

        if observesWorkspaceChanges {
            observeWorkspaceChanges()
        }
    }

    deinit {
        for observerToken in observerTokens {
            notificationCenter.removeObserver(observerToken)
        }
    }

    func refresh() {
        var usedURLs = Set<URL>()
        volumes = loadVolumes()
            .filter(\.shouldAppearInSidebar)
            .filter { volume in
                usedURLs.insert(volume.url.standardizedFileURL).inserted
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func isEjecting(_ volume: MountedVolume) -> Bool {
        ejectingVolumeURLs.contains(volume.url.standardizedFileURL)
    }

    /// Safely unmounts every partition on the selected device before ejecting it.
    /// Rapid duplicate requests are coalesced while the operating-system request
    /// is in flight.
    @discardableResult
    func eject(_ requestedVolume: MountedVolume) async -> Bool {
        let volumeURL = requestedVolume.url.standardizedFileURL
        guard let volume = volumes.first(where: {
            $0.url.standardizedFileURL == volumeURL
        }), volume.supportsUserInitiatedEject else {
            return false
        }
        guard ejectingVolumeURLs.insert(volumeURL).inserted else {
            return false
        }

        ejectFailure = nil
        defer {
            ejectingVolumeURLs.remove(volumeURL)
        }

        do {
            try await ejector.eject(volumeURL)
            volumes.removeAll {
                $0.url.standardizedFileURL == volumeURL
            }
            return true
        } catch {
            ejectFailure = MountedVolumeEjectFailure(
                volume: volume,
                message: error.localizedDescription
            )
            return false
        }
    }

    func dismissEjectFailure() {
        ejectFailure = nil
    }

    private func observeWorkspaceChanges() {
        let notificationNames: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]

        observerTokens = notificationNames.map { notificationName in
            notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
    }
}
