//
//  MountedVolumeTests.swift
//  FinallyExplorerTests
//

import AppKit
import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct MountedVolumeTests {
    @Test("Locations shows only external, removable, ejectable, browsable volumes")
    func filtersAndSortsMountedVolumes() {
        let usb = volume(path: "/Volumes/USB", title: "USB", isInternal: false)
        let archive = volume(
            path: "/Volumes/Archive",
            title: "Archive",
            isInternal: true,
            isEjectable: true
        )
        let internalData = volume(
            path: "/System/Volumes/Data",
            title: "Data",
            isInternal: true
        )
        let inaccessible = volume(
            path: "/Volumes/Hidden",
            title: "Hidden",
            isInternal: false,
            isBrowsable: false
        )
        let root = volume(path: "/", title: "Macintosh HD", isInternal: false)
        let duplicateUSB = volume(
            path: "/Volumes/USB/../USB",
            title: "Duplicate",
            isInternal: false
        )

        let monitor = MountedVolumeMonitor(
            loadVolumes: {
                [usb, internalData, inaccessible, root, duplicateUSB, archive]
            },
            observesWorkspaceChanges: false
        )

        #expect(monitor.volumes.map(\.title) == ["Archive", "USB"])
        #expect(monitor.volumes.map(\.url) == [archive.url, usb.url])
    }

    @Test("Workspace mount notifications refresh the Locations model")
    func mountNotificationRefreshesVolumes() async {
        let notificationCenter = NotificationCenter()
        let usb = volume(path: "/Volumes/USB", title: "USB", isInternal: false)
        var loadedVolumes: [MountedVolume] = []
        let monitor = MountedVolumeMonitor(
            loadVolumes: { loadedVolumes },
            notificationCenter: notificationCenter
        )
        #expect(monitor.volumes.isEmpty)

        loadedVolumes = [usb]
        notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil)

        for _ in 0..<100 where monitor.volumes.isEmpty {
            await Task.yield()
        }
        #expect(monitor.volumes == [usb])
    }

    @Test("Mounted drives are exposed as external-drive sidebar places")
    func sidebarIncludesMountedDrive() {
        let usb = volume(path: "/Volumes/USB", title: "Work USB", isInternal: false)
        let monitor = MountedVolumeMonitor(
            loadVolumes: { [usb] },
            observesWorkspaceChanges: false
        )
        let sidebar = SidebarModel(
            store: MountedSidebarStore(),
            mountedVolumeMonitor: monitor
        )

        let place = sidebar.mountedVolumePlaces.first
        #expect(place?.title == "Work USB")
        #expect(place?.url == usb.url)
        #expect(place?.systemImage == "externaldrive")
        #expect(sidebar.allPlaces.contains { $0.id == place?.id })
    }

    private func volume(
        path: String,
        title: String,
        isInternal: Bool,
        isRemovable: Bool = false,
        isEjectable: Bool = false,
        isBrowsable: Bool = true
    ) -> MountedVolume {
        MountedVolume(
            url: URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL,
            title: title,
            isInternal: isInternal,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isBrowsable: isBrowsable
        )
    }
}

@MainActor
private final class MountedSidebarStore: SidebarFavoriteStoring {
    func loadFavorites() -> [SidebarFavorite] { [] }
    func saveFavorites(_ favorites: [SidebarFavorite]) {}
}
