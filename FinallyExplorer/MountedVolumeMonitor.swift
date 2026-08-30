//
//  MountedVolumeMonitor.swift
//  FinallyExplorer
//

import AppKit
import Observation

/// Keeps the Locations section synchronized with macOS mount changes.
@MainActor
@Observable
final class MountedVolumeMonitor {
    private(set) var volumes: [MountedVolume] = []

    @ObservationIgnored private let loadVolumes: @MainActor () -> [MountedVolume]
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []

    init(
        loadVolumes: @escaping @MainActor () -> [MountedVolume] = {
            MountedVolume.discover()
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        observesWorkspaceChanges: Bool = true
    ) {
        self.loadVolumes = loadVolumes
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
