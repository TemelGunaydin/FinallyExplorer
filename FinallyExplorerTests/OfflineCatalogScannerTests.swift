import Foundation
import Testing
@testable import FinallyExplorer

struct OfflineCatalogScannerTests {
    @Test("Cataloging saves metadata only and never needs to read file contents")
    func metadataOnly() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let file = try fixture.files.write("Reports/Invoice.pdf", "secret contents that must not be stored")
        let before = try ScopedFolderDescriptor(rootURL: file.deletingLastPathComponent()).state(of: file.lastPathComponent)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        let snapshot = try await fixture.scan()
        #expect(snapshot.entries.map(\.relativePath) == ["Reports", "Reports/Invoice.pdf"])
        #expect(snapshot.entries[0].byteCount == nil)
        #expect(snapshot.entries[1].byteCount == before?.size)
        #expect(snapshot.entries[1].inode == before?.inode)
        #expect(snapshot.summary.volumeID == fixture.volume.id)
        #expect(snapshot.summary.relativeRoot.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.storageURL.path) == false)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(encoded.contains("secret contents") == false)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Hidden items are opt-in; packages and links are never traversed")
    func exclusions() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Visible.txt", "data")
        try fixture.files.write(".Hidden/Secret.txt", "hidden")
        try fixture.files.write("Demo.app/Contents/Payload.txt", "not cataloged")
        try fixture.files.write("Outside.txt", "outside", in: fixture.files.destination)
        try FileManager.default.createSymbolicLink(at: fixture.files.source.appending(path: "Link"), withDestinationURL: fixture.files.destination)
        let ordinary = try await fixture.scan()
        #expect(ordinary.entries.map(\.relativePath) == ["Visible.txt"])
        #expect(ordinary.summary.excludedHiddenCount == 1)
        #expect(ordinary.summary.skippedCount == 2)
        let hidden = try await fixture.scan(includesHidden: true)
        #expect(hidden.entries.map(\.relativePath) == [".Hidden", ".Hidden/Secret.txt", "Visible.txt"])
        #expect(hidden.summary.includesHidden)
        #expect(hidden.summary.excludedHiddenCount == 0)
    }

    @Test("Selecting a subfolder records only its relative scope")
    func subfolderScope() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Reports/Invoice.pdf", "data")
        try fixture.files.write("Outside.txt", "not in scope")
        let source = try await fixture.access.source(for: fixture.files.source.appending(path: "Reports"))
        let snapshot = try await OfflineCatalogScanner(volumes: fixture.access).scan(source, includesHidden: false, progress: { _ in })
        #expect(snapshot.summary.relativeRoot == "Reports")
        #expect(snapshot.entries.map(\.relativePath) == ["Invoice.pdf"])
        #expect(try await fixture.access.reveal(snapshot.entries[0], in: snapshot.summary) == fixture.files.source.appending(path: "Reports/Invoice.pdf"))
    }

    @Test("Entry and path byte limits reject the whole scan", arguments: [true, false])
    func boundedScan(_ entryLimit: Bool) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("First.txt", "one")
        try fixture.files.write("Second.txt", "two")
        let source = try await fixture.access.source(for: fixture.files.source)
        let scanner = OfflineCatalogScanner(volumes: fixture.access, entryLimit: entryLimit ? 1 : 100, pathByteLimit: entryLimit ? 1_000 : 3)
        await #expect(throws: FolderComparisonError.limitExceeded) {
            try await scanner.scan(source, includesHidden: false, progress: { _ in })
        }
        #expect(try await fixture.store.list().isEmpty)
    }

    @Test("A scan changed during validation is rejected, not saved partially")
    func changedTree() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let file = try fixture.files.write("Invoice.pdf", "old")
        let source = try await fixture.access.source(for: fixture.files.source)
        await #expect(throws: (any Error).self) {
            try await OfflineCatalogScanner(volumes: fixture.access).scan(source, includesHidden: false) { progress in
                if progress.phase == "Checking catalog snapshot…" { try? Data("changed".utf8).write(to: file) }
            }
        }
    }

    @Test("Disconnected disks keep searchable snapshots but cannot reveal files")
    func offlineMetadata() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let snapshot = try await fixture.scan()
        let saved = try await fixture.store.save(snapshot)
        try FileManager.default.moveItem(at: fixture.files.source, to: fixture.files.root.appending(path: "Disconnected"))
        #expect(try await fixture.access.volumes().isEmpty)
        let loaded = try await fixture.store.load(saved.id)
        let result = try await OfflineCatalogSearch.search(loaded.entries, query: OfflineCatalogQuery(text: "invoice"))
        #expect(result.totalMatches == 1)
        await #expect(throws: OfflineCatalogError.unavailableVolume) {
            try await fixture.access.reveal(loaded.entries[0], in: loaded.summary)
        }
    }

    @Test("The same disk UUID can reconnect at a different mount path")
    func reconnectedMount() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let snapshot = try await fixture.scan()
        let mount = fixture.files.root.appending(path: "Reconnected")
        try FileManager.default.moveItem(at: fixture.files.source, to: mount)
        let access = LocalOfflineVolumeAccess(fixtureVolumes: [OfflineCatalogVolume(id: fixture.volume.id, name: "Renamed Disk", rootURL: mount)])
        let url = try await access.reveal(snapshot.entries[0], in: snapshot.summary)
        #expect(url == mount.appending(path: "Invoice.pdf"))
    }

    @Test("A namesake disk and duplicate UUIDs are not accepted as the original", arguments: [true, false])
    func wrongDisk(_ duplicate: Bool) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let snapshot = try await fixture.scan()
        let other = OfflineCatalogVolume(id: duplicate ? fixture.volume.id : UUID(), name: fixture.volume.name, rootURL: fixture.files.destination)
        let access = LocalOfflineVolumeAccess(fixtureVolumes: duplicate ? [fixture.volume, other] : [other])
        await #expect(throws: duplicate ? OfflineCatalogError.ambiguousVolume : .unavailableVolume) {
            try await access.reveal(snapshot.entries[0], in: snapshot.summary)
        }
    }

    @Test("Replaced files and symlink parents cannot be revealed as saved originals", arguments: [true, false])
    func replacedEntry(_ symlink: Bool) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let file = try fixture.files.write("Reports/Invoice.pdf", "data")
        let snapshot = try await fixture.scan()
        let entry = try #require(snapshot.entries.first { $0.isDirectory == false })
        if symlink {
            try FileManager.default.moveItem(at: file.deletingLastPathComponent(), to: fixture.files.destination.appending(path: "OldReports"))
            try FileManager.default.createSymbolicLink(at: file.deletingLastPathComponent(), withDestinationURL: fixture.files.destination)
        } else {
            try FileManager.default.moveItem(at: file, to: fixture.files.destination.appending(path: "Original.pdf"))
            try fixture.files.write("Reports/Invoice.pdf", "different item")
        }
        await #expect(throws: (any Error).self) { try await fixture.access.reveal(entry, in: snapshot.summary) }
    }

    @Test("Selection outside a supported volume or inside an app package is rejected")
    func invalidSources() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Demo.app/Contents/File.txt", "data")
        await #expect(throws: OfflineCatalogError.invalidSource) { try await fixture.access.source(for: fixture.files.destination) }
        await #expect(throws: OfflineCatalogError.invalidSource) { try await fixture.access.source(for: fixture.files.source.appending(path: "Demo.app")) }
        let remote = try #require(URL(string: "file://other-host/Volume/Folder"))
        await #expect(throws: OfflineCatalogError.invalidSource) { try await fixture.access.source(for: remote) }
    }
}
