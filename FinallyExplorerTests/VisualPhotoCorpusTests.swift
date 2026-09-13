import Foundation
import Testing
@testable import FinallyExplorer

struct VisualPhotoCorpusTests {
    @Test("Actual Vision finds two CC0 beach photographs without returning the forest or city", .timeLimit(.minutes(1)))
    func realPhotos() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let bundle = Bundle(for: VisualPhotoTestResources.self)
        // Anonymous filenames deliberately carry no scene hints.
        let names = ["beach-monterey", "beach-side", "forest", "city"]
        for (index, name) in names.enumerated() {
            let source = try #require(bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures/VisualPhotos")
                ?? bundle.url(forResource: name, withExtension: "jpg"))
            try FileManager.default.copyItem(at: source, to: fixture.source.appending(path: "IMG_\(index).jpg"))
        }
        let snapshot = try await VisualSearchService().scan(rootURL: fixture.source, includesHidden: false)
        #expect(snapshot.entries.count == 4)
        let plan = try await FoundationModelsVisualInterpreter().interpret("Find photos taken by the sea")
        for entry in snapshot.entries {
            print("Photo corpus \(entry.relativePath):", entry.evidence.labels)
        }
        let results = try await plan.search(snapshot.entries)
        #expect(Set(results.map(\.id)) == ["IMG_0.jpg", "IMG_1.jpg"])
        // Every displayed match is still validated against the live file.
        for match in results { _ = try await VisualSearchService().validate(match.entry, in: snapshot) }
    }
}

private final class VisualPhotoTestResources: NSObject { }
