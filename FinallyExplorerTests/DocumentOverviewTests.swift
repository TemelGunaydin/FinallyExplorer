import Foundation
import Testing

@testable import FinallyExplorer

struct DocumentOverviewTests {
    @Test(
        "Overview intent is explicit and does not capture specific fact questions",
        arguments: [
            ("explain the document", true), ("Please summarize this file.", true),
            ("Could you explain this document in simple English?", true),
            ("What is this document about?", true), ("give me an overview of these documents", true),
            ("Explain the payment deadline", false), ("summarize the refund policy", false),
            ("explain this document and invent a price", false), ("What is the invoice total?", false),
        ])
    func intent(_ sample: (String, Bool)) {
        #expect(DocumentOverviewRequest.matches(sample.0) == sample.1)
    }

    @Test("A generic explanation retrieves source text without matching explain as a keyword")
    func genericExplanation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write(
            "LICENSE.txt",
            "Permission is granted to use and distribute the software. Include the copyright notice. The software is provided without warranty."
        )
        let model = await DocumentQuestionModel(
            answerer: QuotingDocumentAnswerer(),
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        await model.select([file])
        await model.readDocuments()?.value
        await MainActor.run { model.question = "explain the document" }
        await model.ask()?.value
        #expect(await model.errorMessage == nil)
        #expect(await model.claims.isEmpty == false)
        #expect(await model.claims.first?.source.fileName == "LICENSE.txt")
        #expect(try String(contentsOf: file, encoding: .utf8).contains("without warranty"))
    }

    @Test("Overview covers every selected file with bounded, exact excerpts", arguments: [1, 2, 5])
    func coverage(_ count: Int) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let urls = try (1...count).map { number in
            try fixture.write(
                "Report \(number).txt",
                (1...30).map { "Section \($0): " + String(repeating: "🌅 Report details. ", count: 20) }.joined(
                    separator: "\n"))
        }
        let documents = try await LocalDocumentReader().read(urls)
        let search = LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder())
        let index = try await search.prepare(documents)
        let result = try await search.retrieve(question: "summarize these documents", index: index)
        #expect(Set(result.passages.map(\.documentID)).count == count)
        #expect(result.passages.count <= max(4, count))
        #expect(result.passages.reduce(0) { $0 + $1.text.utf8.count } <= 2_400)
        #expect(Set(result.passages.map(\.id)).count == result.passages.count)
        for excerpt in result.passages {
            #expect(
                documents.flatMap(\.passages).contains {
                    $0.documentID == excerpt.documentID && $0.text.contains(excerpt.text)
                })
        }
        if count == 1 {
            #expect(result.passages.first?.text.hasPrefix("Section 1:") == true)
            #expect(result.passages.last?.text == index.excerpts.last?.text)
        }
    }

    @Test("Overview retrieval respects cancellation and still rejects invented quotes")
    func cancellationAndValidation() async throws {
        let source = DocumentPassage(
            id: 1, documentID: UUID(), fileName: "Note.txt", page: nil, text: "The office opens on Monday.")
        let index = DocumentRetrievalIndex(excerpts: [source], words: [], vectors: nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalDocumentPassageSearch().retrieve(question: "explain the document", index: index)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let excerpts = try DocumentOverviewRequest.excerpts(from: index)
        let id = try #require(excerpts.first?.id)
        #expect(throws: DocumentQuestionError.invalidAnswer) {
            try DocumentAnswerValidator.validate(
                .init(
                    insufficientEvidence: false,
                    claims: [
                        .init(
                            statement: "The office closes on Friday.", sourceID: id,
                            quote: "The office closes on Friday.")
                    ]), sources: excerpts)
        }
    }
}
