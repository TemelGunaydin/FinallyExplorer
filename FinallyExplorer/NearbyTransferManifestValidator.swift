//
//  NearbyTransferManifestValidator.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferManifestValidator: Sendable {
    func validate(_ manifest: NearbyTransferManifest) throws {
        guard manifest.entries.isEmpty == false else {
            throw NearbyTransferError.invalidManifest("the file list is empty")
        }
        guard manifest.entries.count <= NearbyTransferManifest.maximumEntryCount else {
            throw NearbyTransferError.invalidManifest("too many files")
        }
        guard manifest.totalByteCount <= NearbyTransferManifest.maximumTotalByteCount else {
            throw NearbyTransferError.invalidManifest("the transfer is too large")
        }

        var entryIDs: Set<UUID> = []
        var canonicalPaths: Set<String> = []
        var directoryPaths: Set<String> = []
        var calculatedTotal: UInt64 = 0

        for entry in manifest.entries {
            guard entryIDs.insert(entry.id).inserted else {
                throw NearbyTransferError.invalidManifest("duplicate entry identifier")
            }

            let path = try validatedPath(for: entry.relativePathComponents)
            let canonicalPath = canonical(path)
            guard canonicalPaths.insert(canonicalPath).inserted else {
                throw NearbyTransferError.invalidManifest(
                    "two items resolve to the same name"
                )
            }

            if entry.relativePathComponents.count > 1 {
                let parentPath = entry.relativePathComponents.dropLast().joined(separator: "/")
                guard directoryPaths.contains(canonical(parentPath)) else {
                    throw NearbyTransferError.invalidManifest(
                        "an item has no declared parent folder"
                    )
                }
            }

            switch entry.kind {
            case .directory:
                guard entry.byteCount == 0, entry.sha256 == nil else {
                    throw NearbyTransferError.invalidManifest(
                        "a folder contains file-only metadata"
                    )
                }
                directoryPaths.insert(canonicalPath)

            case .file:
                guard entry.sha256?.count == 32 else {
                    throw NearbyTransferError.invalidManifest(
                        "a file checksum is missing"
                    )
                }
                let (sum, overflow) = calculatedTotal.addingReportingOverflow(
                    entry.byteCount
                )
                guard overflow == false,
                      sum <= NearbyTransferManifest.maximumTotalByteCount else {
                    throw NearbyTransferError.invalidManifest(
                        "the declared size overflows the transfer limit"
                    )
                }
                calculatedTotal = sum
            }
        }

        guard calculatedTotal == manifest.totalByteCount else {
            throw NearbyTransferError.invalidManifest(
                "the total size does not match its files"
            )
        }
        guard manifest.entries.contains(where: {
            $0.relativePathComponents.count == 1
        }) else {
            throw NearbyTransferError.invalidManifest("there is no top-level item")
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded = try encoder.encode(manifest)
        guard encoded.count <= NearbyTransferManifest.maximumEncodedByteCount else {
            throw NearbyTransferError.invalidManifest("the file list is too large")
        }
    }

    private func validatedPath(for components: [String]) throws -> String {
        guard components.isEmpty == false,
              components.count <= NearbyTransferManifest.maximumDepth else {
            throw NearbyTransferError.invalidManifest("invalid folder depth")
        }

        var pathByteCount = 0
        for component in components {
            let byteCount = component.utf8.count
            guard component.isEmpty == false,
                  component != ".",
                  component != "..",
                  component.contains("/") == false,
                  component.contains("\0") == false,
                  byteCount <= 255 else {
                throw NearbyTransferError.invalidManifest("unsafe item name")
            }
            pathByteCount += byteCount + 1
            guard pathByteCount <= 4_096 else {
                throw NearbyTransferError.invalidManifest("an item path is too long")
            }
        }

        return components.joined(separator: "/")
    }

    private func canonical(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
