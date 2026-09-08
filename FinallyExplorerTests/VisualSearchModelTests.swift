import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct VisualSearchModelTests {
    @Test("Selecting a source never scans; matching uses evidence, not filenames")
    func explicitAnalysisAndSearch() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("FilenameOnly.jpg", "bytes")
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        model.setSource(fixture.source)
        #expect(model.snapshot == nil)
        #expect(model.isWorking == false)
        await model.analyze()?.value
        await model.waitForSearch()
        #expect(model.matches.count == 1)
        model.query = "BEACH invoice"
        await model.waitForSearch()
        #expect(model.matches.first?.labels == ["beach"])
        #expect(model.matches.first?.excerpt?.contains("4827") == true)
        model.mode = .labels
        await model.waitForSearch()
        #expect(model.matches.isEmpty)
        model.mode = .text
        model.query = "invoice"
        await model.waitForSearch()
        #expect(model.matches.first?.labels.isEmpty == true)
        model.mode = .both
        model.query = "FilenameOnly"
        await model.waitForSearch()
        #expect(model.matches.isEmpty)
        model.query = "no match"
        model.query = "beach"
        await model.waitForSearch()
        #expect(model.matches.count == 1)
        model.clearIndex()
        await model.waitForSearch()
        #expect(model.snapshot == nil)
        #expect(model.matches.isEmpty)
        #expect(model.query.isEmpty)
    }

    @Test("Cancel and clear reject late completion and block overlapping scans", .timeLimit(.minutes(1)), arguments: [false, true])
    func lateCompletion(_ clear: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "bytes")
        let snapshot = try await VisualSearchService(analyzer: FixedVisualAnalyzer()).scan(rootURL: fixture.source, includesHidden: false)
        let gate = FolderComparisonTestGate()
        let model = VisualSearchModel(service: IgnoringCancellationVisualScanner(snapshot: snapshot, gate: gate))
        model.setSource(fixture.source)
        let task = try #require(model.analyze())
        await gate.waitUntilEntered()
        if clear { model.clearIndex() } else { model.cancel() }
        #expect(model.isWorking)
        #expect(model.isCancelling)
        #expect(model.analyze() == nil)
        await gate.release()
        await task.value
        await model.waitForSearch()
        #expect(model.snapshot == nil)
        #expect(model.matches.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isWorking == false)
        #expect(model.progress == nil)
    }

    @Test("A failed rescan keeps the previous analysis and a source change forgets it")
    func preserveAndForget() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "bytes")
        var service = VisualSearchService(analyzer: FixedVisualAnalyzer())
        service.imageLimit = 1
        let model = VisualSearchModel(service: service)
        model.setSource(fixture.source)
        await model.analyze()?.value
        let previous = try #require(model.snapshot?.id)
        try fixture.write("Another.jpg", "bytes")
        await model.analyze()?.value
        #expect(model.snapshot?.id == previous)
        #expect(model.errorMessage == VisualSearchError.tooManyImages.localizedDescription)
        model.setSource(fixture.destination)
        #expect(model.snapshot == nil)
        #expect(model.matches.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("Hidden opt-in invalidates old evidence and stale reveal never navigates")
    func privacyAndReveal() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Photo.jpg", "bytes")
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        model.setSource(fixture.source)
        await model.analyze()?.value
        let entry = try #require(model.snapshot?.entries.first)
        try Data("changed".utf8).write(to: file)
        var revealed = false
        await model.reveal(entry) { _ in revealed = true }?.value
        #expect(revealed == false)
        #expect(model.errorMessage != nil)
        model.includesHidden = true
        #expect(model.snapshot == nil)
        #expect(model.matches.isEmpty)
    }
}

private nonisolated struct IgnoringCancellationVisualScanner: VisualSearchScanning {
    let snapshot: VisualSearchSnapshot
    let gate: FolderComparisonTestGate
    func scan(rootURL: URL, includesHidden: Bool,
              progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> VisualSearchSnapshot {
        await gate.pause()
        await progress(FolderWorkProgress(phase: "Late progress", relativePath: ""))
        return snapshot
    }
    func validate(_ entry: VisualSearchSnapshot.Entry, in snapshot: VisualSearchSnapshot) async throws -> URL { throw VisualSearchError.changed }
}
