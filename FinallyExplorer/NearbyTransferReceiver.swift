//
//  NearbyTransferReceiver.swift
//  FinallyExplorer
//

import CryptoKit
import Darwin
import Foundation

nonisolated final class NearbyTransferReceiver {
    private let manifest: NearbyTransferManifest
    private let destinationDirectoryURL: URL
    private let stagingDirectoryURL: URL
    private let fileManager: FileManager
    private let entriesByID: [UUID: NearbyTransferManifestEntry]
    private let fileEntryIDs: [UUID]
    private var nextFileIndex = 0
    private var currentEntry: NearbyTransferManifestEntry?
    private var currentHandle: FileHandle?
    private var currentHasher = SHA256()
    private var currentByteCount: UInt64 = 0
    private var ownsStagingDirectory = false

    init(
        manifest: NearbyTransferManifest,
        destinationDirectoryURL: URL,
        stagingIdentifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws {
        try NearbyTransferManifestValidator().validate(manifest)

        let destination = destinationDirectoryURL.standardizedFileURL
        let values = try? destination.resourceValues(forKeys: [
            .isDirectoryKey,
            .isWritableKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard values?.isDirectory == true, values?.isWritable != false else {
            throw NearbyTransferError.destinationUnavailable
        }
        guard Self.hasSufficientSpace(
            for: manifest.totalByteCount,
            importantUsageCapacity: values?.volumeAvailableCapacityForImportantUsage,
            basicCapacity: values?.volumeAvailableCapacity
        ) else {
            throw NearbyTransferError.insufficientSpace
        }

        self.manifest = manifest
        self.destinationDirectoryURL = destination
        self.fileManager = fileManager
        stagingDirectoryURL = destination.appending(
            path: ".finallyexplorer-transfer-\(stagingIdentifier.uuidString)",
            directoryHint: .isDirectory
        )
        entriesByID = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.id, $0) })
        fileEntryIDs = manifest.entries.filter { $0.kind == .file }.map(\.id)

        var didCreateStagingDirectory = false
        do {
            let creationResult = Darwin.mkdir(
                stagingDirectoryURL.path(percentEncoded: false),
                S_IRWXU
            )
            guard creationResult == 0 else {
                throw NearbyTransferError.destinationUnavailable
            }
            didCreateStagingDirectory = true
            ownsStagingDirectory = true
            for entry in manifest.entries where entry.kind == .directory {
                try fileManager.createDirectory(
                    at: stagedURL(for: entry),
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        } catch {
            if didCreateStagingDirectory {
                cleanupOwnedStagingDirectory()
            }
            throw NearbyTransferError.destinationUnavailable
        }
    }

    deinit {
        try? currentHandle?.close()
        cleanupOwnedStagingDirectory()
    }

    func startFile(entryID: UUID) throws {
        guard currentEntry == nil,
              nextFileIndex < fileEntryIDs.count,
              fileEntryIDs[nextFileIndex] == entryID,
              let entry = entriesByID[entryID],
              entry.kind == .file else {
            throw NearbyTransferError.protocolViolation("unexpected file start")
        }

        let targetURL = stagedURL(for: entry)
        let descriptor = Darwin.open(
            targetURL.path(percentEncoded: false),
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw NearbyTransferError.destinationUnavailable
        }

        currentEntry = entry
        currentHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        currentHasher = SHA256()
        currentByteCount = 0
    }

    func writeChunk(entryID: UUID, offset: UInt64, data: Data) throws {
        guard let entry = currentEntry,
              entry.id == entryID,
              let handle = currentHandle,
              offset == currentByteCount,
              data.count <= NearbyTransferWire.fileChunkByteCount else {
            throw NearbyTransferError.protocolViolation("unexpected file data")
        }
        let (newCount, overflow) = currentByteCount.addingReportingOverflow(
            UInt64(data.count)
        )
        guard overflow == false, newCount <= entry.byteCount else {
            throw NearbyTransferError.protocolViolation("file exceeds its declared size")
        }

        try handle.write(contentsOf: data)
        currentHasher.update(data: data)
        currentByteCount = newCount
    }

    func finishFile(entryID: UUID) throws {
        guard let entry = currentEntry,
              entry.id == entryID,
              let handle = currentHandle,
              currentByteCount == entry.byteCount,
              Data(currentHasher.finalize()) == entry.sha256 else {
            throw NearbyTransferError.protocolViolation(
                "a received file failed verification"
            )
        }

        try handle.synchronize()
        try handle.close()
        currentHandle = nil
        currentEntry = nil
        currentByteCount = 0
        nextFileIndex += 1

        if let modificationDate = entry.modificationDate {
            try? fileManager.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: stagedURL(for: entry).path(percentEncoded: false)
            )
        }
    }

    func commit() throws -> [URL] {
        guard currentEntry == nil, nextFileIndex == fileEntryIDs.count else {
            throw NearbyTransferError.protocolViolation("the transfer ended early")
        }

        let rootEntries = manifest.entries.filter {
            $0.relativePathComponents.count == 1
        }
        var moves: [(source: URL, destination: URL)] = []
        var reservedNames: Set<String> = []
        for entry in rootEntries {
            let destination = uniqueDestination(
                for: entry,
                reserving: &reservedNames
            )
            moves.append((stagedURL(for: entry), destination))
        }

        var completedMoves: [(source: URL, destination: URL)] = []
        do {
            for move in moves {
                try fileManager.moveItem(
                    at: move.source,
                    to: move.destination
                )
                completedMoves.append(move)
            }
        } catch {
            for move in completedMoves.reversed() {
                try? fileManager.moveItem(
                    at: move.destination,
                    to: move.source
                )
            }
            throw NearbyTransferError.destinationUnavailable
        }

        cleanupOwnedStagingDirectory()
        return moves.map(\.destination)
    }

    func cancel() {
        try? currentHandle?.close()
        currentHandle = nil
        currentEntry = nil
        cleanupOwnedStagingDirectory()
    }

    static func hasSufficientSpace(
        for byteCount: UInt64,
        importantUsageCapacity: Int64?,
        basicCapacity: Int?
    ) -> Bool {
        let required = byteCount.addingReportingOverflow(64 * 1_024 * 1_024)
        guard required.overflow == false else { return false }

        if let importantUsageCapacity, importantUsageCapacity > 0 {
            return required.partialValue <= UInt64(importantUsageCapacity)
        }
        if let basicCapacity, basicCapacity > 0 {
            return required.partialValue <= UInt64(basicCapacity)
        }

        // A filesystem may not report capacity at all. Let writes surface the
        // eventual error, but honor an explicit zero-capacity report.
        return importantUsageCapacity != 0 && basicCapacity != 0
    }

    private func stagedURL(for entry: NearbyTransferManifestEntry) -> URL {
        entry.relativePathComponents.reduce(stagingDirectoryURL) { partial, component in
            partial.appending(path: component)
        }
    }

    private func uniqueDestination(
        for entry: NearbyTransferManifestEntry,
        reserving names: inout Set<String>
    ) -> URL {
        let originalName = entry.displayName
        let originalURL = URL(filePath: originalName)
        let pathExtension = entry.kind == .file ? originalURL.pathExtension : ""
        let stem = pathExtension.isEmpty
            ? originalName
            : originalURL.deletingPathExtension().lastPathComponent
        var candidateName = originalName
        var suffix = 2

        while names.contains(candidateName.precomposedStringWithCanonicalMapping.lowercased())
            || fileManager.fileExists(
                atPath: destinationDirectoryURL.appending(path: candidateName)
                    .path(percentEncoded: false)
            ) {
            candidateName = pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            suffix += 1
        }
        names.insert(candidateName.precomposedStringWithCanonicalMapping.lowercased())
        return destinationDirectoryURL.appending(
            path: candidateName,
            directoryHint: entry.kind == .directory ? .isDirectory : .notDirectory
        )
    }

    private func cleanupOwnedStagingDirectory() {
        guard ownsStagingDirectory else { return }
        do {
            try fileManager.removeItem(at: stagingDirectoryURL)
            ownsStagingDirectory = false
        } catch {
            // Keep ownership so a later cancel or deinit can retry cleanup.
        }
    }
}
