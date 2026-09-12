import Foundation
import NaturalLanguage
import Testing
@testable import FinallyExplorer

@Suite(.serialized, .enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil))
struct LocalDocumentSemanticSearchTests {
    @Test("Local sentence meaning retrieves evidence with different vocabulary", arguments: [
        ("How can I get my money back?", "Customers may request a refund within thirty days of purchase."),
        ("How long can staff take a holiday?", "Employees receive twenty days of paid vacation annually."),
        ("How do I end my membership?", "Subscriptions can be cancelled by contacting customer support."),
        ("Where can I leave my car?", "Visitor parking is available in the underground garage.")
    ])
    func paraphrases(_ sample: (String, String)) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let relevant = try fixture.write("Policy.txt", sample.1)
        let other = try fixture.write("Office.txt", "The office walls are painted blue. Bicycles should be parked behind the building.")
        let documents = try await LocalDocumentReader().read([other, relevant])
        let search = LocalDocumentPassageSearch()
        let index = try await search.prepare(documents)
        #expect(index.supportsSemanticSearch)
        let result = try await search.retrieve(question: sample.0, index: index)
        let queryVector = try #require(try await LocalDocumentSemanticEncoder().vectors(for: [sample.0])?.first)
        let similarities = (index.vectors ?? []).map { vector in zip(queryVector, vector).reduce(0) { $0 + $1.0 * $1.1 } }
        let lexical = try await LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()).prepare(documents)
        let keywords = try await search.retrieve(question: sample.0, index: lexical)
        #expect(keywords.passages.contains { $0.fileName == "Policy.txt" } == false)
        #expect(result.usedSemanticSearch)
        #expect(result.passages.first?.fileName == "Policy.txt", "Candidate cosine similarities: \(similarities)")
        #expect(result.passages.first?.text == sample.1)
    }

    @Test("Unrelated questions do not retrieve a financial deadline", arguments: [
        "What is the spaceship velocity?",
        "How tall is Mount Everest?",
        "Which planet has the largest rings?",
        "What does a seahorse eat?"
    ])
    func unrelated(_ question: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let search = LocalDocumentPassageSearch()
        let index = try await search.prepare(LocalDocumentReader().read([file]))
        let result = try await search.retrieve(question: question, index: index)
        #expect(result.passages.isEmpty)
    }

    @Test("The maximum total text budget prepares locally without re-embedding documents for each question", .timeLimit(.minutes(1)))
    func boundedCorpus() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let text = String(String(repeating: "Customers may request a refund within thirty days of purchase. ", count: 3_000).prefix(150_000))
        let first = try fixture.write("Policy A.txt", text)
        let second = try fixture.write("Policy B.txt", text)
        let search = LocalDocumentPassageSearch()
        let documents = try await LocalDocumentReader().read([first, second])
        let index = try await search.prepare(documents)
        #expect(index.supportsSemanticSearch)
        #expect(index.vectors?.count == index.excerpts.count)
        #expect(index.excerpts.count < 1_000)
        let result = try await search.retrieve(question: "refund", index: index)
        #expect(result.passages.count == 4)
    }
}
