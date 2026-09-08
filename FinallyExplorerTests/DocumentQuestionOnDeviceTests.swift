import Foundation
import FoundationModels
import Testing
@testable import FinallyExplorer

@Suite(.serialized, .enabled(if: SystemLanguageModel.default.availability == .available))
struct DocumentQuestionOnDeviceTests {
    @Test("The real local model answers with a verified quote from PDF page two", .timeLimit(.minutes(1)))
    func groundedAnswer() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let url = fixture.source.appending(path: "Invoice.pdf")
        try DocumentQuestionFixtures.pdf(pages: ["Invoice 4827", "The payment deadline is 30 September 2026."]).write(to: url)
        let documents = try await LocalDocumentReader().read([url])
        let question = "What is the payment deadline?"
        let sources = try await DocumentPassageRetriever.retrieve(question: question, documents: documents)
        let draft = try await FoundationModelsDocumentAnswerer().answer(question: question, sources: sources)
        let claims = try DocumentAnswerValidator.validate(draft, sources: sources)
        #expect(claims.isEmpty == false)
        #expect(claims.contains { $0.source.page == 2 && $0.quote.contains("30 September 2026") })
    }

    @Test("The real model does not invent a price absent from supplied evidence", .timeLimit(.minutes(1)))
    func missingFact() async throws {
        let source = DocumentPassage(id: 1, documentID: UUID(), fileName: "Report.txt", page: nil, text: "The payment deadline is Friday. The price is not specified.")
        let draft = try await FoundationModelsDocumentAnswerer().answer(question: "How much is the price in dollars?", sources: [source])
        if draft.insufficientEvidence { #expect(draft.claims.isEmpty) }
        else {
            let claims = try DocumentAnswerValidator.validate(draft, sources: [source])
            #expect(claims.allSatisfy { $0.statement.rangeOfCharacter(from: .decimalDigits) == nil })
        }
    }
}
