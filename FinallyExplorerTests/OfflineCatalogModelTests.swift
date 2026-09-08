import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct OfflineCatalogModelTests {
    @Test("Choosing a source never scans or saves until Scan & Save is requested")
    func explicitOptIn() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let model = OfflineCatalogModel(store: fixture.store, volumes: fixture.access)
        await model.load()?.value
        #expect(model.catalogs.isEmpty)
        #expect(model.scanAndSave() == nil)
        await model.prepare(fixture.files.source)?.value
        #expect(model.source?.volume.id == fixture.volume.id)
        #expect(try await fixture.store.list().isEmpty)
        await model.scanAndSave()?.value
        await model.waitForSearch()
        #expect(model.rows.map(\.relativePath) == ["Invoice.pdf"])
        #expect(model.catalogs.count == 1)
        #expect(model.source == nil)
        #expect(model.errorMessage == nil)
        #expect(model.notice == "Catalog saved · 1 entries")
    }

    @Test("Canceled scans reject late completion and keep an existing saved catalog", .timeLimit(.minutes(1)))
    func cancelledScan() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Original.pdf", "data")
        let saved = try await fixture.store.save(fixture.scan())
        try fixture.files.write("New.pdf", "new")
        let incoming = try await fixture.scan()
        let gate = FolderComparisonTestGate()
        let model = OfflineCatalogModel(store: fixture.store, volumes: fixture.access, scanner: DelayedOfflineScanner(snapshot: incoming, gate: gate))
        await model.load()?.value
        let work = try #require(model.refreshSelected())
        await gate.waitUntilEntered()
        #expect(model.refreshSelected() == nil)
        model.cancel()
        #expect(model.isCancelling)
        await gate.release(); await work.value
        #expect(model.isWorking == false)
        #expect(model.catalogs == [saved])
        #expect(try await fixture.store.load(saved.id).entries.map(\.relativePath) == ["Original.pdf"])
    }

    @Test("Query changes and clearing selection cannot publish stale rows")
    func staleQueries() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "one")
        try fixture.files.write("Photo.png", "two")
        _ = try await fixture.store.save(fixture.scan())
        let model = OfflineCatalogModel(store: fixture.store, volumes: fixture.access)
        await model.load()?.value
        model.query = "invoice"; model.query = "photo"
        await model.waitForSearch()
        #expect(model.rows.map(\.relativePath) == ["Photo.png"])
        model.query = "invoice"
        model.selectedID = nil
        await model.waitForSearch()
        #expect(model.rows.isEmpty)
        #expect(model.totalMatches == 0)
        #expect(model.isSearching == false)
    }

    @Test("Selecting another catalog clears old rows while its payload loads", .timeLimit(.minutes(1)))
    func switchingCatalogs() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Reports/Invoice.pdf", "data")
        let first = try await fixture.store.save(fixture.scan())
        let source = try await fixture.access.source(for: fixture.files.source.appending(path: "Reports"))
        let second = try await fixture.store.save(OfflineCatalogScanner(volumes: fixture.access).scan(source, includesHidden: false, progress: { _ in }))
        let gate = FolderComparisonTestGate()
        let store = GatedOfflineStore(base: fixture.store, loadID: second.id, gate: gate)
        let model = OfflineCatalogModel(store: store, volumes: fixture.access)
        await model.load()?.value
        #expect(model.selectedID == first.id)
        model.query = "Reports"
        model.selectedID = second.id
        await gate.waitUntilEntered()
        await model.waitForSearch()
        #expect(model.rows.isEmpty)
        await gate.release(); await model.waitForWork()
        model.query = "invoice"
        await model.waitForSearch()
        #expect(model.rows.map(\.relativePath) == ["Invoice.pdf"])
    }

    @Test("Metadata removal requires confirmation and never deletes the original")
    func removalConfirmation() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        let file = try fixture.files.write("Invoice.pdf", "keep")
        let saved = try await fixture.store.save(fixture.scan())
        let model = OfflineCatalogModel(store: fixture.store, volumes: fixture.access)
        await model.load()?.value
        #expect(model.confirmRemoval(saved) == nil)
        model.removal = saved; model.removal = nil
        #expect(try await fixture.store.list() == [saved])
        model.removal = saved
        await model.confirmRemoval(saved)?.value
        #expect(model.catalogs.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(try await fixture.store.list().isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test("Offline metadata remains searchable, while revealing the source is refused")
    func offlineReveal() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        _ = try await fixture.store.save(fixture.scan())
        let model = OfflineCatalogModel(store: fixture.store, volumes: LocalOfflineVolumeAccess(fixtureVolumes: []))
        await model.load()?.value
        model.query = "invoice"; await model.waitForSearch()
        #expect(model.isConnected == false)
        #expect(model.connectionDescription == "Disk offline — saved metadata")
        let row = try #require(model.rows.first)
        await model.reveal(row) { _, _ in Issue.record("An offline location must not be revealed") }?.value
        #expect(model.errorMessage == OfflineCatalogError.unavailableVolume.localizedDescription)
        #expect(model.rows == [row])
    }

    @Test("Refresh preserves the catalog's original hidden-item choice")
    func refreshScopeOptions() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Visible.txt", "data")
        try fixture.files.write(".Hidden.txt", "hidden")
        _ = try await fixture.store.save(fixture.scan(includesHidden: true))
        let model = OfflineCatalogModel(store: fixture.store, volumes: fixture.access)
        await model.load()?.value
        model.includesHidden = false
        await model.refreshSelected()?.value
        await model.waitForSearch()
        #expect(model.selected?.includesHidden == true)
        #expect(model.rows.count == 2)
    }

    @Test("Cancellation after a committed save still reports the saved result", .timeLimit(.minutes(1)))
    func cancellationAfterCommit() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let gate = FolderComparisonTestGate()
        let model = OfflineCatalogModel(store: GatedOfflineStore(base: fixture.store, saveGate: gate), volumes: fixture.access)
        await model.prepare(fixture.files.source)?.value
        let work = try #require(model.scanAndSave())
        await gate.waitUntilEntered()
        model.cancel(); await gate.release(); await work.value
        #expect(model.catalogs.count == 1)
        #expect(model.notice == "Catalog saved · 1 entries")
        #expect(try await fixture.store.list() == model.catalogs)
    }

    @Test("A cleanup-only failure removes the stale registry row and explains the remaining cache")
    func cleanupFailure() async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Invoice.pdf", "data")
        let saved = try await fixture.store.save(fixture.scan())
        let model = OfflineCatalogModel(store: GatedOfflineStore(base: fixture.store, failCleanup: true), volumes: fixture.access)
        await model.load()?.value
        model.removal = saved
        await model.confirmRemoval(saved)?.value
        #expect(model.catalogs.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.errorMessage == OfflineCatalogError.cleanupFailed.localizedDescription)
    }
}

private nonisolated struct DelayedOfflineScanner: OfflineCatalogScanning {
    let snapshot: OfflineCatalogSnapshot
    let gate: FolderComparisonTestGate
    func scan(_ source: OfflineCatalogSource, includesHidden: Bool,
              progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> OfflineCatalogSnapshot {
        await gate.pause()
        await progress(FolderWorkProgress(phase: "Late scan", relativePath: ""))
        return snapshot
    }
}

private actor GatedOfflineStore: OfflineCatalogStoring {
    let base: OfflineCatalogStore
    let loadID: UUID?
    let gate: FolderComparisonTestGate?
    let saveGate: FolderComparisonTestGate?
    let failCleanup: Bool

    init(base: OfflineCatalogStore, loadID: UUID? = nil, gate: FolderComparisonTestGate? = nil,
         saveGate: FolderComparisonTestGate? = nil, failCleanup: Bool = false) {
        self.base = base; self.loadID = loadID; self.gate = gate; self.saveGate = saveGate; self.failCleanup = failCleanup
    }
    func list() async throws -> [OfflineCatalogSummary] { try await base.list() }
    func load(_ id: UUID) async throws -> OfflineCatalogSnapshot {
        if id == loadID { await gate?.pause() }
        return try await base.load(id)
    }
    func save(_ snapshot: OfflineCatalogSnapshot) async throws -> OfflineCatalogSummary {
        let saved = try await base.save(snapshot)
        await saveGate?.pause()
        return saved
    }
    func remove(_ id: UUID) async throws {
        try await base.remove(id)
        if failCleanup { throw OfflineCatalogError.cleanupFailed }
    }
}
