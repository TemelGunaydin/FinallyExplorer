import Foundation
import Testing
@testable import FinallyExplorer

struct DocumentAnswerValidatorTests {
    private let source = DocumentPassage(id: 1, documentID: UUID(), fileName: "Invoice.pdf", page: 2,
        text: "The payment deadline is 30 September 2026. The total is 480 USD.")

    @Test("Every answer statement must cite a real source and a contiguous exact quote")
    func validatesQuotes() throws {
        let draft = DocumentAnswerDraft(insufficientEvidence: false, claims: [.init(statement: "Payment is due on 30 September 2026.", sourceID: 1,
            quote: "The payment deadline is 30 September 2026.")])
        let claims = try DocumentAnswerValidator.validate(draft, sources: [source])
        #expect(claims[0].source.page == 2)
        #expect(claims[0].quote == draft.claims[0].quote)
    }

    @Test("Fabricated citations, paraphrased quotes, and uncited answers are rejected", arguments: ["wrong-id", "fake-quote", "no-claims", "short-quote"])
    func rejects(_ kind: String) {
        let quote = kind == "fake-quote" ? "The payment deadline is 12 December 2027." : kind == "short-quote" ? "The" : source.text
        let draft = DocumentAnswerDraft(insufficientEvidence: false, claims: kind == "no-claims" ? [] : [.init(statement: "Answer", sourceID: kind == "wrong-id" ? 99 : 1, quote: quote)])
        #expect(throws: DocumentQuestionError.invalidAnswer) { try DocumentAnswerValidator.validate(draft, sources: [source]) }
    }

    @Test("Insufficient evidence is shown as a refusal, not a sourced answer")
    func insufficient() {
        #expect(throws: DocumentQuestionError.noEvidence) {
            try DocumentAnswerValidator.validate(.init(insufficientEvidence: true, claims: []), sources: [source])
        }
    }
}
