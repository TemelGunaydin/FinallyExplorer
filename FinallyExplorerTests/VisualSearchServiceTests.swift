import Foundation
import ImageIO
import Testing
@testable import FinallyExplorer

struct VisualSearchServiceTests {
    @Test("Real Vision classification and English OCR read synthetic image bytes", .timeLimit(.minutes(1)))
    func actualVision() async throws {
        let evidence = try await VisionImageAnalyzer().analyze(VisualSearchTestFixtures.receiptImage())
        #expect(evidence.text.localizedCaseInsensitiveContains("INVOICE"))
        #expect(evidence.text.contains("4827"))
        #expect(evidence.text.count <= 4_000)
        #expect(evidence.textWasTruncated == false)
        #expect(evidence.labels.isEmpty == false)
        #expect(evidence.labels.count <= 12)
        #expect(evidence.labels.allSatisfy { $0.confidence >= 0.2 })
        #expect(evidence.thumbnail.count < 100_000)
        let source = try #require(CGImageSourceCreateWithData(evidence.thumbnail as CFData, nil))
        let values = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((values[kCGImagePropertyPixelWidth] as? Int ?? .max) <= 240)
    }

    @Test("Malformed images are rejected by ImageIO without calling Vision")
    func invalidBytes() async {
        await #expect(throws: VisualSearchError.unreadableImage) {
            try await VisionImageAnalyzer().analyze(Data("not an image".utf8))
        }
    }

    @Test("Scan follows the explicit image scope, preserving originals and excluding hidden/link/package entries")
    func scope() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let image = try fixture.write("Nested/Photo.PNG", "image fixture")
        try fixture.write("Ignore.txt", "text")
        try fixture.write(".Hidden.jpg", "hidden")
        try fixture.write("Demo.app/Private.jpg", "package")
        try fixture.write("Unsupported.svg", "svg")
        try FileManager.default.createSymbolicLink(at: fixture.source.appending(path: "Link.jpg"), withDestinationURL: image)
        let service = VisualSearchService(analyzer: FixedVisualAnalyzer())
        let snapshot = try await service.scan(rootURL: fixture.source, includesHidden: false)
        #expect(snapshot.entries.map(\.relativePath) == ["Nested/Photo.PNG"])
        #expect(snapshot.excludedHiddenCount == 1)
        #expect(snapshot.excludedOtherCount == 2)
        #expect(snapshot.skipped.isEmpty)
        #expect(try await service.validate(snapshot.entries[0], in: snapshot) == image)
        #expect(try String(contentsOf: image, encoding: .utf8) == "image fixture")
        let hidden = try await service.scan(rootURL: fixture.source, includesHidden: true)
        #expect(Set(hidden.entries.map(\.relativePath)) == [".Hidden.jpg", "Nested/Photo.PNG"])
    }

    @Test("Folder and image limits fail explicitly, never return a partial index")
    func limits() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.jpg", "a")
        try fixture.write("B.jpg", "b")
        var service = VisualSearchService(analyzer: FixedVisualAnalyzer())
        service.imageLimit = 1
        await #expect(throws: VisualSearchError.tooManyImages) { try await service.scan(rootURL: fixture.source, includesHidden: false) }
        service.imageLimit = 300
        service.entryLimit = 1
        await #expect(throws: FolderComparisonError.limitExceeded) { try await service.scan(rootURL: fixture.source, includesHidden: false) }
    }

    @Test("A corrupt supported image is reported as skipped")
    func skipped() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Corrupt.png", "broken")
        let result = try await VisualSearchService().scan(rootURL: fixture.source, includesHidden: false)
        #expect(result.entries.isEmpty)
        #expect(result.skipped.map(\.relativePath) == ["Corrupt.png"])
    }

    @Test("Oversized files are skipped without decoding and package roots are rejected")
    func oversizedAndPackage() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Large.jpg", "")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 41 * 1_024 * 1_024)
        try handle.close()
        let service = VisualSearchService(analyzer: FixedVisualAnalyzer())
        let result = try await service.scan(rootURL: fixture.source, includesHidden: false)
        #expect(result.entries.isEmpty)
        #expect(result.skipped.first?.reason == VisualSearchError.imageTooLarge.localizedDescription)
        try fixture.write("Example.app/Photo.jpg", "package")
        await #expect(throws: VisualSearchError.invalidFolder) {
            try await service.scan(rootURL: fixture.source.appending(path: "Example.app"), includesHidden: false)
        }
    }

    @Test("A Vision backend failure is an error, not a successful empty analysis")
    func backendFailure() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "bytes")
        await #expect(throws: VisualSearchError.unavailable) {
            try await VisualSearchService(analyzer: FailingVisualAnalyzer()).scan(rootURL: fixture.source, includesHidden: false)
        }
        #expect(VisualSearchError.message(for: FolderComparisonError.limitExceeded).contains("25,000"))
        #expect(VisualSearchError.message(for: FolderComparisonError.changed("Photo.jpg")) == VisualSearchError.changed.localizedDescription)
    }

    @Test("Changing a file during analysis invalidates the entire snapshot", .timeLimit(.minutes(1)))
    func changedDuringScan() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Photo.jpg", "before")
        let gate = FolderComparisonTestGate()
        let task = Task { try await VisualSearchService(analyzer: PausedVisualAnalyzer(gate: gate)).scan(rootURL: fixture.source, includesHidden: false) }
        await gate.waitUntilEntered()
        try Data("after modification".utf8).write(to: file)
        await gate.release()
        do { _ = try await task.value; Issue.record("A changed file produced a snapshot") }
        catch let error as FolderComparisonError {
            guard case .changed = error else { Issue.record("Unexpected folder error: \(error)"); return }
        }
    }

    @Test("Reveal refuses changed files and symlink-swapped parent folders", arguments: [false, true])
    func staleReveal(_ replaceParent: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Nested/Photo.jpg", "before")
        let service = VisualSearchService(analyzer: FixedVisualAnalyzer())
        let snapshot = try await service.scan(rootURL: fixture.source, includesHidden: false)
        if replaceParent {
            let nested = file.deletingLastPathComponent()
            let moved = fixture.destination.appending(path: "Moved")
            try FileManager.default.moveItem(at: nested, to: moved)
            try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: moved)
        } else { try Data("changed".utf8).write(to: file) }
        do { _ = try await service.validate(snapshot.entries[0], in: snapshot); Issue.record("Stale result was revealed") }
        catch is VisualSearchError { #expect(replaceParent == false) }
        catch is FolderComparisonError { #expect(replaceParent) }
    }

    @Test("Network URLs, the whole Mac and package roots cannot be analyzed", arguments: ["https://example.com/pictures", "file://example.com/pictures", "file:///"])
    func invalidScope(_ path: String) async throws {
        let url = try #require(URL(string: path))
        await #expect(throws: VisualSearchError.invalidFolder) {
            try await VisualSearchService().scan(rootURL: url, includesHidden: false)
        }
    }
}

private nonisolated struct FailingVisualAnalyzer: VisualImageAnalyzing {
    func analyze(_ data: Data) async throws -> VisualImageEvidence { throw CocoaError(.featureUnsupported) }
}
