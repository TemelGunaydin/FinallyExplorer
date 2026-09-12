import Foundation
import Testing
@testable import FinallyExplorer

struct DocumentFollowUpPolicyTests {
    @Test("Singular references after an explicit plural question require a named subject", arguments: [
        ("Which studios have invoices?", "When was it issued?", true),
        ("Compare the two invoices.", "What is its total?", true),
        ("List the outstanding invoices.", "When is that due?", true),
        ("What are the outstanding payments?", "How much is it?", true),
        ("When is Harbor's invoice due?", "When was it issued?", false),
        ("Which studios have invoices?", "When was Harbor's invoice issued?", false),
        ("When was Harbor's invoice issued?", "What about Cedar?", false)
    ])
    func singularReference(_ sample: (String, String, Bool)) {
        let turn = DocumentQuestionTurn(question: sample.0, resolvedQuestion: sample.0, claims: [])
        #expect(DocumentFollowUpPolicy.requiresNamedSubject(question: sample.1, context: [DocumentFollowUpContext(turn: turn)]) == sample.2)
    }
}
