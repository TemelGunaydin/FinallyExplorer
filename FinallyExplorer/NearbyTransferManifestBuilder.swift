//
//  NearbyTransferManifestBuilder.swift
//  FinallyExplorer
//

import CryptoKit
import Foundation

nonisolated struct NearbyTransferManifestBuilder: Sendable {
    private var fileManager: FileManager { FileManager() }

    @concurrent
    func build(from sourceURLs: [URL]) async throws -> NearbyTransferPackage {
        let roots = normalizedRoots(sourceURLs)
        guard roots.isEmpty == false else {
            throw NearbyTransferError.invalidSource("no file or folder was selected")
        }

        var entries: [NearbyTransferManifestEntry] = []
        var sources: [UUID: URL] = [:]
        var usedRootNames: Set<String> = []
        var totalByteCount: UInt64 = 0

        for rootURL in roots {
            let rootName = uniqueRootName(
                preferredName: rootURL.lastPathComponent,
                usedNames: &usedRootNames
            )
            try appendEntry(
                at: rootURL,
                relativePathComponents: [rootName],
                entries: &entries,
                sources: &sources,
                totalByteCount: &totalByteCount
            )

            let rootValues = try resourceValues(for: rootURL)
            guard rootValues.isSymbolicLink != true else {
                throw NearbyTransferError.invalidSource(
                    "symbolic links are not supported"
                )
            }
            guard rootValues.isDirectory == true else { continue }

            let remainingEntryCapacity = NearbyTransferManifest.maximumEntryCount
                - entries.count
            var descendants = try descendantURLs(
                below: rootURL,
                maximumCount: remainingEntryCapacity
            ).map { url in
                (
                    url: url,
                    relativePathComponents: try relativeComponents(
                        for: url,
                        below: rootURL
                    )
                )
            }

            descendants.sort {
                let left = $0.relativePathComponents
                let right = $1.relativePathComponents
                if left.count != right.count { return left.count < right.count }
                return left.joined(separator: "/").localizedStandardCompare(
                    right.joined(separator: "/")
                ) == .orderedAscending
            }

            for descendant in descendants {
                try appendEntry(
                    at: descendant.url,
                    relativePathComponents: [rootName] + descendant.relativePathComponents,
                    entries: &entries,
                    sources: &sources,
                    totalByteCount: &totalByteCount
                )
            }
        }

        let manifest = NearbyTransferManifest(
            transferID: UUID(),
            entries: entries,
            totalByteCount: totalByteCount
        )
        try NearbyTransferManifestValidator().validate(manifest)
        return NearbyTransferPackage(
            manifest: manifest,
            sourceURLsByEntryID: sources
        )
    }

    private func appendEntry(
        at url: URL,
        relativePathComponents: [String],
        entries: inout [NearbyTransferManifestEntry],
        sources: inout [UUID: URL],
        totalByteCount: inout UInt64
    ) throws {
        guard entries.count < NearbyTransferManifest.maximumEntryCount else {
            throw NearbyTransferError.invalidSource("too many files were selected")
        }

        let values = try resourceValues(for: url)
        guard values.isSymbolicLink != true else {
            throw NearbyTransferError.invalidSource(
                "symbolic links are not supported"
            )
        }

        let id = UUID()
        if values.isDirectory == true {
            entries.append(
                NearbyTransferManifestEntry(
                    id: id,
                    relativePathComponents: relativePathComponents,
                    kind: .directory,
                    byteCount: 0,
                    sha256: nil,
                    modificationDate: values.contentModificationDate
                )
            )
            return
        }

        guard values.isRegularFile == true else {
            throw NearbyTransferError.invalidSource(
                "special files such as sockets and devices are not supported"
            )
        }

        let fileSize = UInt64(max(0, values.fileSize ?? 0))
        let (newTotal, overflow) = totalByteCount.addingReportingOverflow(fileSize)
        guard overflow == false,
              newTotal <= NearbyTransferManifest.maximumTotalByteCount else {
            throw NearbyTransferError.invalidSource("the selection is too large")
        }

        let digest = try checksum(of: url)
        entries.append(
            NearbyTransferManifestEntry(
                id: id,
                relativePathComponents: relativePathComponents,
                kind: .file,
                byteCount: fileSize,
                sha256: digest,
                modificationDate: values.contentModificationDate
            )
        )
        sources[id] = url
        totalByteCount = newTotal
    }

    private func checksum(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), data.isEmpty == false {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }

    private func descendantURLs(
        below rootURL: URL,
        maximumCount: Int
    ) throws -> [URL] {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw NearbyTransferError.invalidSource(
                "\(rootURL.lastPathComponent) cannot be read"
            )
        }

        var descendants: [URL] = []
        for case let descendantURL as URL in enumerator {
            try Task.checkCancellation()
            guard descendants.count < maximumCount else {
                throw NearbyTransferError.invalidSource("too many files were selected")
            }
            let values = try resourceValues(for: descendantURL)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw NearbyTransferError.invalidSource(
                    "symbolic links are not supported"
                )
            }
            descendants.append(descendantURL)
        }
        if enumerationError != nil {
            throw NearbyTransferError.invalidSource(
                "\(rootURL.lastPathComponent) cannot be completely read"
            )
        }
        return descendants
    }

    private func resourceValues(for url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: Self.resourceKeys)
        } catch {
            throw NearbyTransferError.invalidSource(
                "\(url.lastPathComponent) cannot be read"
            )
        }
    }

    private func normalizedRoots(_ urls: [URL]) -> [URL] {
        let sorted = Set(urls.map(\.standardizedFileURL)).sorted {
            $0.pathComponents.count < $1.pathComponents.count
        }
        var roots: [URL] = []

        for candidate in sorted {
            let candidatePath = candidate.path(percentEncoded: false)
            let isDescendant = roots.contains { root in
                let rootPath = root.path(percentEncoded: false)
                return candidatePath == rootPath
                    || candidatePath.hasPrefix(rootPath.hasSuffix("/")
                        ? rootPath
                        : rootPath + "/")
            }
            if isDescendant == false {
                roots.append(candidate)
            }
        }
        return roots
    }

    private func relativeComponents(
        for url: URL,
        below rootURL: URL
    ) throws -> [String] {
        // FileManager may canonicalize system aliases while enumerating (for example,
        // `/var` becomes `/private/var`). Compare canonical paths so that the alias
        // does not accidentally become part of the transfer's relative path.
        let rootComponents = rootURL.resolvingSymlinksInPath().pathComponents
        let itemComponents = url.resolvingSymlinksInPath().pathComponents
        guard itemComponents.count > rootComponents.count,
              Array(itemComponents.prefix(rootComponents.count)) == rootComponents else {
            throw NearbyTransferError.invalidSource(
                "an item resolved outside its selected folder"
            )
        }

        return Array(itemComponents.dropFirst(rootComponents.count))
    }

    private func uniqueRootName(
        preferredName: String,
        usedNames: inout Set<String>
    ) -> String {
        let baseName = preferredName.isEmpty ? "Item" : preferredName
        var candidate = baseName
        var suffix = 2
        while usedNames.insert(candidate.precomposedStringWithCanonicalMapping.lowercased())
            .inserted == false {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]
}
