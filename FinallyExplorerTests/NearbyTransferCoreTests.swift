//
//  NearbyTransferCoreTests.swift
//  FinallyExplorerTests
//

import CryptoKit
import Foundation
import Testing
@testable import FinallyExplorer

struct NearbyTransferCoreTests {
    @Test("Manifest builder includes regular files and empty folders")
    func builderIncludesFileAndEmptyFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = root.appending(path: "Selection", directoryHint: .isDirectory)
        let emptyFolder = selection.appending(path: "Empty", directoryHint: .isDirectory)
        let fileURL = selection.appending(path: "note.txt")
        let contents = Data("nearby transfer".utf8)
        try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: false)
        try contents.write(to: fileURL)

        let package = try await NearbyTransferManifestBuilder().build(from: [selection])
        let entriesByPath = Dictionary(
            uniqueKeysWithValues: package.manifest.entries.map {
                ($0.relativePathComponents.joined(separator: "/"), $0)
            }
        )
        let fileEntry = try #require(entriesByPath["Selection/note.txt"])

        #expect(entriesByPath["Selection"]?.kind == .directory)
        #expect(entriesByPath["Selection/Empty"]?.kind == .directory)
        #expect(fileEntry.kind == .file)
        #expect(fileEntry.byteCount == UInt64(contents.count))
        #expect(fileEntry.sha256 == Data(SHA256.hash(data: contents)))
        #expect(package.manifest.totalByteCount == UInt64(contents.count))
        #expect(
            package.sourceURLsByEntryID[fileEntry.id]?.resolvingSymlinksInPath()
                == fileURL.resolvingSymlinksInPath()
        )
    }

    @Test("Manifest builder rejects symbolic links without following them")
    func builderRejectsSymbolicLinks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = root.appending(path: "Selection", directoryHint: .isDirectory)
        let target = root.appending(path: "outside.txt")
        let link = selection.appending(path: "linked.txt")
        try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        do {
            _ = try await NearbyTransferManifestBuilder().build(from: [selection])
            Issue.record("A symbolic link must not enter a nearby-transfer manifest.")
        } catch NearbyTransferError.invalidSource {
            // Expected.
        } catch {
            Issue.record("Unexpected symbolic-link error: \(error)")
        }
    }

    @Test(
        "Manifest validator rejects unsafe or internally inconsistent manifests",
        arguments: InvalidManifestCase.allCases
    )
    func validatorRejectsInvalidManifest(testCase: InvalidManifestCase) {
        do {
            try NearbyTransferManifestValidator().validate(testCase.manifest)
            Issue.record("Expected invalid manifest to be rejected: \(testCase.rawValue)")
        } catch NearbyTransferError.invalidManifest {
            // Expected.
        } catch {
            Issue.record("Unexpected validation error for \(testCase.rawValue): \(error)")
        }
    }

    @Test("Cryptors exchange authenticated messages in both directions")
    func cryptorsRoundTripInBothDirections() throws {
        var pair = try makeCryptorPair()
        let senderMessage = Data("sender to receiver".utf8)
        let receiverMessage = Data("receiver to sender".utf8)

        let senderPayload = try pair.initiator.seal(senderMessage, type: .fileChunk)
        let openedByReceiver = try pair.receiver.open(senderPayload, type: .fileChunk)
        let receiverPayload = try pair.receiver.seal(receiverMessage, type: .transferDecision)
        let openedBySender = try pair.initiator.open(receiverPayload, type: .transferDecision)

        #expect(openedByReceiver == senderMessage)
        #expect(openedBySender == receiverMessage)
        #expect(pair.initiator.pairingCode == pair.receiver.pairingCode)
        #expect(pair.initiator.transcriptHash == pair.receiver.transcriptHash)
    }

    @Test("Cryptor rejects ciphertext tampering and replayed sequence numbers")
    func cryptorRejectsTamperAndReplay() throws {
        var tamperPair = try makeCryptorPair()
        var tampered = try tamperPair.initiator.seal(Data("auth".utf8), type: .fileChunk)
        tampered[8] ^= 0x01

        do {
            _ = try tamperPair.receiver.open(tampered, type: .fileChunk)
            Issue.record("Tampered ciphertext must fail authentication.")
        } catch NearbyTransferError.protocolViolation {
            // Expected.
        } catch {
            Issue.record("Unexpected tamper error: \(error)")
        }

        var replayPair = try makeCryptorPair()
        let payload = try replayPair.initiator.seal(Data("once".utf8), type: .fileChunk)
        _ = try replayPair.receiver.open(payload, type: .fileChunk)

        do {
            _ = try replayPair.receiver.open(payload, type: .fileChunk)
            Issue.record("An already consumed encrypted frame must not be accepted twice.")
        } catch NearbyTransferError.protocolViolation {
            // Expected.
        } catch {
            Issue.record("Unexpected replay error: \(error)")
        }
    }

    @Test("Receiver stages invisibly, verifies bytes, and commits the complete tree")
    func receiverStagesAndCommitsTree() throws {
        let destination = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let contents = Data("verified payload".utf8)
        let fixture = makeFolderManifest(contents: contents)
        let stagingURL = stagingURL(for: fixture.manifest, in: destination)
        let receiver = try NearbyTransferReceiver(
            manifest: fixture.manifest,
            destinationDirectoryURL: destination,
            stagingIdentifier: fixture.manifest.transferID
        )

        #expect(stagingURL.lastPathComponent.hasPrefix("."))
        #expect(FileManager.default.fileExists(atPath: stagingURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: stagingURL.appending(path: "Archive/Empty").path
            )
        )

        try receiver.startFile(entryID: fixture.fileEntry.id)
        try receiver.writeChunk(entryID: fixture.fileEntry.id, offset: 0, data: contents)
        try receiver.finishFile(entryID: fixture.fileEntry.id)
        let committedURLs = try receiver.commit()
        let committedRoot = try #require(committedURLs.first)

        #expect(FileManager.default.fileExists(atPath: stagingURL.path) == false)
        #expect(committedRoot.lastPathComponent == "Archive")
        #expect(try Data(contentsOf: committedRoot.appending(path: "payload.bin")) == contents)
        #expect(
            FileManager.default.fileExists(
                atPath: committedRoot.appending(path: "Empty").path
            )
        )
    }

    @Test("Receiver preserves an existing destination by choosing a collision-safe name")
    func receiverRenamesCollision() throws {
        let destination = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let existingURL = destination.appending(path: "note.txt")
        try Data("existing".utf8).write(to: existingURL)
        let incoming = Data("incoming".utf8)
        let entry = fileEntry(path: ["note.txt"], contents: incoming)
        let manifest = NearbyTransferManifest(
            transferID: fixedUUID("00000000-0000-0000-0000-000000000031"),
            entries: [entry],
            totalByteCount: UInt64(incoming.count)
        )
        let receiver = try NearbyTransferReceiver(
            manifest: manifest,
            destinationDirectoryURL: destination
        )

        try receiver.startFile(entryID: entry.id)
        try receiver.writeChunk(entryID: entry.id, offset: 0, data: incoming)
        try receiver.finishFile(entryID: entry.id)
        let committed = try #require(receiver.commit().first)

        #expect(committed.lastPathComponent == "note 2.txt")
        #expect(try Data(contentsOf: existingURL) == Data("existing".utf8))
        #expect(try Data(contentsOf: committed) == incoming)
    }

    @Test(
        "Receiver cancel removes staging after malformed file data",
        arguments: ReceiverFailureCase.allCases
    )
    func receiverCleansStagingAfterFailure(testCase: ReceiverFailureCase) throws {
        let destination = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let expected = Data("expected".utf8)
        let entry = fileEntry(path: ["payload.bin"], contents: expected)
        let manifest = NearbyTransferManifest(
            transferID: testCase.transferID,
            entries: [entry],
            totalByteCount: UInt64(expected.count)
        )
        let stagingURL = stagingURL(for: manifest, in: destination)
        let receiver = try NearbyTransferReceiver(
            manifest: manifest,
            destinationDirectoryURL: destination,
            stagingIdentifier: manifest.transferID
        )
        try receiver.startFile(entryID: entry.id)

        do {
            switch testCase {
            case .wrongOffset:
                try receiver.writeChunk(entryID: entry.id, offset: 1, data: expected)
            case .wrongChecksum:
                try receiver.writeChunk(
                    entryID: entry.id,
                    offset: 0,
                    data: Data(repeating: 0xFF, count: expected.count)
                )
                try receiver.finishFile(entryID: entry.id)
            }
            Issue.record("Malformed file data must not be accepted: \(testCase.rawValue)")
        } catch NearbyTransferError.protocolViolation {
            // Expected.
        } catch {
            Issue.record("Unexpected receiver error for \(testCase.rawValue): \(error)")
        }

        receiver.cancel()

        #expect(FileManager.default.fileExists(atPath: stagingURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "payload.bin").path) == false)
    }

    @Test("Receiver never deletes a pre-existing path after a staging collision")
    func receiverPreservesPreexistingStagingCollision() throws {
        let destination = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let contents = Data("must survive".utf8)
        let entry = fileEntry(path: ["payload.bin"], contents: contents)
        let manifest = NearbyTransferManifest(
            transferID: fixedUUID("00000000-0000-0000-0000-000000000061"),
            entries: [entry],
            totalByteCount: UInt64(contents.count)
        )
        let stagingIdentifier = fixedUUID("00000000-0000-0000-0000-000000000062")
        let preexistingDirectory = destination.appending(
            path: ".finallyexplorer-transfer-\(stagingIdentifier.uuidString)",
            directoryHint: .isDirectory
        )
        let sentinelURL = preexistingDirectory.appending(path: "keep.txt")
        try FileManager.default.createDirectory(
            at: preexistingDirectory,
            withIntermediateDirectories: false
        )
        try contents.write(to: sentinelURL)

        do {
            _ = try NearbyTransferReceiver(
                manifest: manifest,
                destinationDirectoryURL: destination,
                stagingIdentifier: stagingIdentifier
            )
            Issue.record("A staging collision must reject the incoming transfer.")
        } catch NearbyTransferError.destinationUnavailable {
            // Expected.
        } catch {
            Issue.record("Unexpected staging collision error: \(error)")
        }

        #expect(try Data(contentsOf: sentinelURL) == contents)
    }

    @Test("Receiver falls back when important-usage capacity is spuriously zero")
    func receiverCapacityFallback() {
        let reservePlusPayload = 64 * 1_024 * 1_024 + 512

        #expect(NearbyTransferReceiver.hasSufficientSpace(
            for: 512,
            importantUsageCapacity: 0,
            basicCapacity: reservePlusPayload
        ))
        #expect(NearbyTransferReceiver.hasSufficientSpace(
            for: 512,
            importantUsageCapacity: nil,
            basicCapacity: nil
        ))
        #expect(NearbyTransferReceiver.hasSufficientSpace(
            for: 512,
            importantUsageCapacity: 0,
            basicCapacity: 0
        ) == false)
    }

    @Test("Receiver prefers a positive important-usage capacity report")
    func receiverPrefersImportantUsageCapacity() {
        let reservePlusPayload = 64 * 1_024 * 1_024 + 512

        #expect(NearbyTransferReceiver.hasSufficientSpace(
            for: 512,
            importantUsageCapacity: Int64(reservePlusPayload),
            basicCapacity: 1
        ))
    }

    @Test("Receiver deinit removes its uncommitted staging directory")
    func receiverDeinitCleansOwnedStaging() throws {
        let destination = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let contents = Data("unfinished".utf8)
        let entry = fileEntry(path: ["pending.bin"], contents: contents)
        let manifest = NearbyTransferManifest(
            transferID: fixedUUID("00000000-0000-0000-0000-000000000071"),
            entries: [entry],
            totalByteCount: UInt64(contents.count)
        )
        let stagingURL = stagingURL(for: manifest, in: destination)
        weak var releasedReceiver: NearbyTransferReceiver?

        do {
            let receiver = try NearbyTransferReceiver(
                manifest: manifest,
                destinationDirectoryURL: destination,
                stagingIdentifier: manifest.transferID
            )
            releasedReceiver = receiver
            try receiver.startFile(entryID: entry.id)
            try receiver.writeChunk(
                entryID: entry.id,
                offset: 0,
                data: Data(contents.prefix(1))
            )

            #expect(FileManager.default.fileExists(atPath: stagingURL.path))
        }

        #expect(releasedReceiver == nil)
        #expect(FileManager.default.fileExists(atPath: stagingURL.path) == false)
    }

    private func makeCryptorPair() throws -> (
        initiator: NearbyTransferCryptor,
        receiver: NearbyTransferCryptor
    ) {
        let sessionID = fixedUUID("00000000-0000-0000-0000-000000000041")
        let initiatorHandshake = try NearbyTransferHandshake(identity: NearbyTransferIdentity(
            deviceID: fixedUUID("00000000-0000-0000-0000-000000000042"),
            name: "Sender Mac"
        ))
        let receiverHandshake = try NearbyTransferHandshake(identity: NearbyTransferIdentity(
            deviceID: fixedUUID("00000000-0000-0000-0000-000000000043"),
            name: "Receiver Mac"
        ))
        let initiator = try NearbyTransferCryptor(
            handshake: initiatorHandshake,
            remoteReveal: receiverHandshake.reveal,
            initiatorReveal: initiatorHandshake.reveal,
            receiverReveal: receiverHandshake.reveal,
            sessionID: sessionID,
            isInitiator: true
        )
        let receiver = try NearbyTransferCryptor(
            handshake: receiverHandshake,
            remoteReveal: initiatorHandshake.reveal,
            initiatorReveal: initiatorHandshake.reveal,
            receiverReveal: receiverHandshake.reveal,
            sessionID: sessionID,
            isInitiator: false
        )
        return (initiator, receiver)
    }

    private func makeFolderManifest(contents: Data) -> (
        manifest: NearbyTransferManifest,
        fileEntry: NearbyTransferManifestEntry
    ) {
        let root = directoryEntry(
            id: fixedUUID("00000000-0000-0000-0000-000000000011"),
            path: ["Archive"]
        )
        let empty = directoryEntry(
            id: fixedUUID("00000000-0000-0000-0000-000000000012"),
            path: ["Archive", "Empty"]
        )
        let file = fileEntry(
            id: fixedUUID("00000000-0000-0000-0000-000000000013"),
            path: ["Archive", "payload.bin"],
            contents: contents
        )
        let manifest = NearbyTransferManifest(
            transferID: fixedUUID("00000000-0000-0000-0000-000000000014"),
            entries: [root, empty, file],
            totalByteCount: UInt64(contents.count)
        )
        return (manifest, file)
    }

    private func fileEntry(
        id: UUID = UUID(),
        path: [String],
        contents: Data
    ) -> NearbyTransferManifestEntry {
        NearbyTransferManifestEntry(
            id: id,
            relativePathComponents: path,
            kind: .file,
            byteCount: UInt64(contents.count),
            sha256: Data(SHA256.hash(data: contents)),
            modificationDate: nil
        )
    }

    private func directoryEntry(
        id: UUID = UUID(),
        path: [String]
    ) -> NearbyTransferManifestEntry {
        NearbyTransferManifestEntry(
            id: id,
            relativePathComponents: path,
            kind: .directory,
            byteCount: 0,
            sha256: nil,
            modificationDate: nil
        )
    }

    private func stagingURL(
        for manifest: NearbyTransferManifest,
        in destination: URL
    ) -> URL {
        destination.appending(
            path: ".finallyexplorer-transfer-\(manifest.transferID.uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FinallyExplorerNearbyTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value) ?? UUID()
    }
}

enum InvalidManifestCase: String, CaseIterable, Sendable {
    case traversal
    case duplicatePath
    case totalMismatch

    var manifest: NearbyTransferManifest {
        let checksum = Data(repeating: 0xA5, count: 32)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000021") ?? UUID()
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000022") ?? UUID()
        let transferID = UUID(uuidString: "00000000-0000-0000-0000-000000000023") ?? UUID()

        let entries: [NearbyTransferManifestEntry]
        let total: UInt64
        switch self {
        case .traversal:
            entries = [NearbyTransferManifestEntry(
                id: firstID,
                relativePathComponents: ["..", "escape.txt"],
                kind: .file,
                byteCount: 1,
                sha256: checksum,
                modificationDate: nil
            )]
            total = 1
        case .duplicatePath:
            entries = [
                NearbyTransferManifestEntry(
                    id: firstID,
                    relativePathComponents: ["Report.txt"],
                    kind: .file,
                    byteCount: 1,
                    sha256: checksum,
                    modificationDate: nil
                ),
                NearbyTransferManifestEntry(
                    id: secondID,
                    relativePathComponents: ["report.txt"],
                    kind: .file,
                    byteCount: 1,
                    sha256: checksum,
                    modificationDate: nil
                ),
            ]
            total = 2
        case .totalMismatch:
            entries = [NearbyTransferManifestEntry(
                id: firstID,
                relativePathComponents: ["payload.bin"],
                kind: .file,
                byteCount: 4,
                sha256: checksum,
                modificationDate: nil
            )]
            total = 5
        }

        return NearbyTransferManifest(
            transferID: transferID,
            entries: entries,
            totalByteCount: total
        )
    }
}

enum ReceiverFailureCase: String, CaseIterable, Sendable {
    case wrongOffset
    case wrongChecksum

    var transferID: UUID {
        let suffix = self == .wrongOffset ? "51" : "52"
        return UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)") ?? UUID()
    }
}
