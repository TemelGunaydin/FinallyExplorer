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
        let source = MountedVolumeSource()
        let monitor = MountedVolumeMonitor(
            loadVolumes: { source.volumes },
            notificationCenter: notificationCenter
        )
        #expect(monitor.volumes.isEmpty)

        source.volumes = [usb]
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

    @Test("Successful eject coalesces duplicate requests and removes the disk")
    func successfulEjectCoalescesDuplicateRequests() async throws {
        let usb = volume(
            path: "/Volumes/Work USB",
            title: "Work USB",
            isInternal: false,
            isRemovable: true,
            isEjectable: true
        )
        let ejector = SuspendedMountedVolumeEjector()
        let monitor = MountedVolumeMonitor(
            loadVolumes: { [usb] },
            ejector: ejector,
            observesWorkspaceChanges: false
        )

        let firstRequest = Task {
            await monitor.eject(usb)
        }
        await ejector.waitUntilRequestCount(1)

        #expect(monitor.isEjecting(usb))
        #expect(await monitor.eject(usb) == false)
        #expect(await ejector.requestCount == 1)

        await ejector.succeed()
        #expect(await firstRequest.value)
        #expect(monitor.isEjecting(usb) == false)
        #expect(monitor.volumes.isEmpty)
        #expect(monitor.ejectFailure == nil)
        #expect(await ejector.requestedURLs == [usb.url])
    }

    @Test("External drives remain ejectable when macOS omits the ejectable flag")
    func externalDriveWithoutEjectableMetadataCanBeEjected() async {
        let usb = volume(
            path: "/Volumes/Metadata-Light USB",
            title: "Metadata-Light USB",
            isInternal: false,
            isRemovable: false,
            isEjectable: false
        )
        let ejector = RecordingMountedVolumeEjector()
        let monitor = MountedVolumeMonitor(
            loadVolumes: { [usb] },
            ejector: ejector,
            observesWorkspaceChanges: false
        )

        #expect(usb.supportsUserInitiatedEject)
        #expect(await monitor.eject(usb))
        #expect(await ejector.requestedURLs == [usb.url])
        #expect(monitor.volumes.isEmpty)
    }

    @Test("Failed eject restores the control and keeps the disk visible")
    func failedEjectKeepsVolumeAndPublishesReason() async {
        let usb = volume(
            path: "/Volumes/Busy USB",
            title: "Busy USB",
            isInternal: false,
            isRemovable: true,
            isEjectable: true
        )
        let monitor = MountedVolumeMonitor(
            loadVolumes: { [usb] },
            ejector: FailingMountedVolumeEjector(message: "The disk is in use."),
            observesWorkspaceChanges: false
        )

        #expect(await monitor.eject(usb) == false)
        #expect(monitor.isEjecting(usb) == false)
        #expect(monitor.volumes == [usb])
        #expect(monitor.ejectFailure?.volume == usb)
        #expect(monitor.ejectFailure?.message == "The disk is in use.")

        monitor.dismissEjectFailure()
        #expect(monitor.ejectFailure == nil)
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
private final class MountedVolumeSource {
    var volumes: [MountedVolume] = []
}

private actor SuspendedMountedVolumeEjector: MountedVolumeEjecting {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var requestedURLs: [URL] = []

    var requestCount: Int { requestedURLs.count }

    func eject(_ volumeURL: URL) async throws {
        requestedURLs.append(volumeURL)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        while requestedURLs.count < expectedCount {
            await Task.yield()
        }
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RecordingMountedVolumeEjector: MountedVolumeEjecting {
    private(set) var requestedURLs: [URL] = []

    func eject(_ volumeURL: URL) async throws {
        requestedURLs.append(volumeURL)
    }
}

private struct FailingMountedVolumeEjector: MountedVolumeEjecting {
    let message: String

    func eject(_ volumeURL: URL) async throws {
        throw TestMountedVolumeEjectError(message: message)
    }
}

private struct TestMountedVolumeEjectError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
private final class MountedSidebarStore: SidebarFavoriteStoring {
    func loadFavorites() -> [SidebarFavorite] { [] }
    func saveFavorites(_ favorites: [SidebarFavorite]) {}
}
