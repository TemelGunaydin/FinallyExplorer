import Foundation
import Testing
@testable import FinallyExplorer

struct OfflineCatalogStoreTests {
    @Test("No cache is created until an explicit save; snapshots survive a new store instance")
    func persistenceAndNoImplicitWrites() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        #expect(try await fixture.store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.storageURL.path) == false)
        try fixture.files.write("Invoice.pdf", "private document body")
        let snapshot = try await fixture.scan()
        let saved = try await fixture.store.save(snapshot)
        let reopened = OfflineCatalogStore(rootURL: fixture.storageURL)
        #expect(try await reopened.list() == [saved])
        #expect(try await reopened.load(saved.id).entries == snapshot.entries)
        let permissions = try FileManager.default.attributesOfItem(atPath: fixture.storageURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test("Refreshing a scope replaces its snapshot without making a duplicate catalog")
    func refreshKeepsID() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("First.pdf", "one")
        let first = try await fixture.store.save(fixture.scan())
        try fixture.files.write("Second.pdf", "two")
        let refreshed = try await fixture.store.save(fixture.scan(includesHidden: true))
        #expect(first.id == refreshed.id)
        #expect(refreshed.includesHidden)
        #expect(try await fixture.store.list() == [refreshed])
        #expect(try await fixture.store.load(first.id).entries.count == 2)
        let payloads = try FileManager.default.contentsOfDirectory(at: fixture.storageURL.appending(path: first.id.uuidString), includingPropertiesForKeys: nil)
        #expect(payloads.count == 1)
    }

    @Test("Canceling before publication preserves the previous catalog", .timeLimit(.minutes(1)))
    func cancelledSave() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("First.pdf", "one")
        let saved = try await fixture.store.save(fixture.scan())
        try fixture.files.write("Second.pdf", "two")
        let incoming = try await fixture.scan()
        let gate = FolderComparisonTestGate()
        let task = Task {
            await gate.pause()
            return try await fixture.store.save(incoming)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await fixture.store.list() == [saved])
        #expect(try await fixture.store.load(saved.id).entries.map(\.relativePath) == ["First.pdf"])
    }

    @Test("Removing a saved catalog does not touch any original files")
    func removeMetadataOnly() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let file = try fixture.files.write("Invoice.pdf", "keep original")
        let saved = try await fixture.store.save(fixture.scan())
        try await fixture.store.remove(saved.id)
        #expect(try await fixture.store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.storageURL.appending(path: saved.id.uuidString).path) == false)
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep original")
        try await fixture.store.remove(saved.id)
    }

    @Test("A malformed or newer manifest is reported and never silently replaced", arguments: ["not json", "{\"version\":2,\"records\":[]}"])
    func corruptManifest(_ text: String) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let snapshot = try await fixture.scan()
        _ = try await fixture.store.save(snapshot)
        let manifest = fixture.storageURL.appending(path: "catalogs-v1.json")
        try Data(text.utf8).write(to: manifest, options: .atomic)
        await #expect(throws: OfflineCatalogError.invalidCatalog) { try await fixture.store.list() }
        await #expect(throws: OfflineCatalogError.invalidCatalog) { try await fixture.store.save(snapshot) }
        #expect(try String(contentsOf: manifest, encoding: .utf8) == text)
    }

    @Test("Unreadable payloads fail independently of the catalog registry", arguments: [true, false])
    func corruptOrMissingPayload(_ missing: Bool) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let saved = try await fixture.store.save(fixture.scan())
        let directory = fixture.storageURL.appending(path: saved.id.uuidString)
        let payload = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        if missing { try FileManager.default.removeItem(at: payload) }
        else { try Data("broken".utf8).write(to: payload) }
        await #expect(throws: (any Error).self) { try await fixture.store.load(saved.id) }
        #expect(try await fixture.store.list() == [saved])
        try await fixture.store.remove(saved.id)
        #expect(try await fixture.store.list().isEmpty)
    }

    @Test("Unsafe relative paths cannot enter the catalog", arguments: ["../escape", "/absolute", "a//b", "a/./b", "a/../b", "a\0b", ""])
    func invalidPaths(_ path: String) {
        #expect(throws: OfflineCatalogError.invalidCatalog) { try OfflineCatalogValidation.path(path) }
    }

    @Test("A snapshot with duplicate entries is rejected before disk writes")
    func duplicateEntries() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let original = try await fixture.scan()
        let invalid = OfflineCatalogSnapshot(summary: original.summary, entries: original.entries + original.entries)
        await #expect(throws: OfflineCatalogError.invalidCatalog) { try await fixture.store.save(invalid) }
        #expect(FileManager.default.fileExists(atPath: fixture.storageURL.path) == false)
    }

    @Test("A catalog whose entire payload directory is missing can still be removed")
    func missingDirectoryRemoval() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let saved = try await fixture.store.save(fixture.scan())
        try FileManager.default.removeItem(at: fixture.storageURL.appending(path: saved.id.uuidString))
        try await fixture.store.remove(saved.id)
        #expect(try await fixture.store.list().isEmpty)
    }

    @Test("Oversized payloads are refused before allocation")
    func oversizedPayload() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let saved = try await fixture.store.save(fixture.scan())
        let directory = fixture.storageURL.appending(path: saved.id.uuidString)
        let payload = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let file = try FileHandle(forWritingTo: payload)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(OfflineCatalogValidation.payloadByteLimit + 1))
        await #expect(throws: OfflineCatalogError.invalidCatalog) { try await fixture.store.load(saved.id) }
    }

    @Test("Failed scans cannot replace an already saved payload")
    func changedScanPreservesSave() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("First.txt", "keep")
        let saved = try await fixture.store.save(fixture.scan())
        try fixture.files.write("Second.txt", "new")
        let source = try await fixture.access.source(for: fixture.files.source)
        await #expect(throws: FolderComparisonError.limitExceeded) {
            let snapshot = try await OfflineCatalogScanner(volumes: fixture.access, entryLimit: 1).scan(source, includesHidden: false, progress: { _ in })
            _ = try await fixture.store.save(snapshot)
        }
        #expect(try await fixture.store.list() == [saved])
        #expect(try await fixture.store.load(saved.id).entries.map(\.relativePath) == ["First.txt"])
    }
}
