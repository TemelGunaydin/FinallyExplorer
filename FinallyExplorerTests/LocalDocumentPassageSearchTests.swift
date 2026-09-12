import Foundation
import Testing
@testable import FinallyExplorer

struct LocalDocumentPassageSearchTests {
    @Test("Prepared vectors are reused; only the new question is embedded on each ask")
    func reuse() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Policy.txt", "Customers can request a refund within thirty days.")
        let encoder = RecordingDocumentEncoder()
        let search = LocalDocumentPassageSearch(encoder: encoder)
        let index = try await search.prepare(LocalDocumentReader().read([file]))
        let first = try await search.retrieve(question: "money back", index: index)
        let second = try await search.retrieve(question: "refund period", index: index)
        #expect(first.usedSemanticSearch && second.usedSemanticSearch)
        #expect(first.passages.first?.fileName == "Policy.txt")
        #expect(await encoder.batches.map(\.count) == [1, 1, 1])
        #expect(await encoder.batches.suffix(2) == [["money back"], ["refund period"]])
    }

    @Test("Unavailable or malformed vectors fall back to keywords", arguments: [false, true])
    func fallback(_ malformed: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Invoice.txt", "Harbor invoice payment is due Friday.")
        let encoder: any DocumentSemanticEncoding = malformed ? MalformedDocumentEncoder() : UnavailableDocumentSemanticEncoder()
        let search = LocalDocumentPassageSearch(encoder: encoder)
        let index = try await search.prepare(LocalDocumentReader().read([file]))
        #expect(index.supportsSemanticSearch == false)
        let match = try await search.retrieve(question: "When is Harbor invoice payment due?", index: index)
        #expect(match.usedSemanticSearch == false)
        #expect(match.passages.first?.fileName == "Invoice.txt")
        let none = try await search.retrieve(question: "spaceship velocity", index: index)
        #expect(none.passages.isEmpty)
    }

    @Test("Semantic candidates never exceed four unique citation IDs and remain original excerpts")
    func citationBudget() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        var urls: [URL] = []
        for number in 1...5 {
            urls.append(try fixture.write("Policy \(number).txt", String(repeating: "Refund policy terms. ", count: 100)))
        }
        let documents = try await LocalDocumentReader().read(urls)
        let search = LocalDocumentPassageSearch(encoder: RecordingDocumentEncoder())
        let index = try await search.prepare(documents)
        let result = try await search.retrieve(question: "money back", index: index)
        #expect(result.passages.count == 4)
        #expect(Set(result.passages.map(\.id)).count == 4)
        for excerpt in result.passages {
            #expect(excerpt.text.utf8.count <= 600)
            let original = try #require(documents.flatMap(\.passages).first { $0.id == excerpt.id })
            #expect(original.text.contains(excerpt.text))
            #expect(original.documentID == excerpt.documentID && original.page == excerpt.page)
        }
    }

    @Test("Evidence at the end of a multibyte passage is indexed without breaking citation boundaries")
    func unicodeTail() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Invoice.txt", String(repeating: "🌅", count: 190) + " The invoice total is 480 USD.")
        let documents = try await LocalDocumentReader().read([file])
        let search = LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder())
        let index = try await search.prepare(documents)
        #expect(index.excerpts.count > 1)
        #expect(index.excerpts.allSatisfy { $0.text.utf8.count <= 600 })
        let result = try await search.retrieve(question: "invoice total", index: index)
        let excerpt = try #require(result.passages.first)
        #expect(excerpt.text.contains("The invoice total is 480 USD."))
        #expect(documents[0].passages[0].text.contains(excerpt.text))
    }

    @Test("A missing query vector uses keywords even when prepared vectors exist")
    func missingQueryVector() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Policy.txt", "Employees receive annual vacation.")
        let search = LocalDocumentPassageSearch(encoder: RecordingDocumentEncoder(omitQuery: true))
        let index = try await search.prepare(LocalDocumentReader().read([file]))
        #expect(index.supportsSemanticSearch)
        let result = try await search.retrieve(question: "vacation", index: index)
        #expect(result.usedSemanticSearch == false)
        #expect(result.passages.count == 1)
    }

    @Test("Cancelling a question embedding discards even a late vector", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Policy.txt", "Employees receive annual vacation.")
        let gate = FolderComparisonTestGate()
        let search = LocalDocumentPassageSearch(encoder: RecordingDocumentEncoder(queryGate: gate))
        let index = try await search.prepare(LocalDocumentReader().read([file]))
        let work = Task { try await search.retrieve(question: "vacation", index: index) }
        await gate.waitUntilEntered()
        work.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }
    }
}
