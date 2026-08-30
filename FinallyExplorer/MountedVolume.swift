//
//  MountedVolume.swift
//  FinallyExplorer
//

import Foundation

/// A mounted, browsable file-system volume that can be shown in Locations.
nonisolated struct MountedVolume: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isBrowsable: Bool

    var id: URL { url }

    var shouldAppearInSidebar: Bool {
        url.standardizedFileURL != URL(filePath: "/", directoryHint: .isDirectory)
            && isBrowsable
            && (isInternal == false || isRemovable || isEjectable)
    }

    var sidebarPlace: SidebarPlace {
        .location(url, title: title, systemImage: "externaldrive")
    }

    static func discover(
        fileManager: FileManager = .default
    ) -> [Self] {
        let resourceKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsBrowsableKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
        ]
        let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(resourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                return nil
            }

            let normalizedURL = url.standardizedFileURL
            let fallbackTitle = normalizedURL.lastPathComponent.isEmpty
                ? normalizedURL.path(percentEncoded: false)
                : normalizedURL.lastPathComponent
            return Self(
                url: normalizedURL,
                title: values.volumeName ?? fallbackTitle,
                isInternal: values.volumeIsInternal ?? true,
                isRemovable: values.volumeIsRemovable ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                isBrowsable: values.volumeIsBrowsable ?? false
            )
        }
    }
}
