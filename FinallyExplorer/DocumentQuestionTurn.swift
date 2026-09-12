import Foundation

nonisolated struct DocumentQuestionTurn: Identifiable, Sendable {
    let id = UUID()
    let question: String
    let resolvedQuestion: String
    let claims: [DocumentAnswerClaim]
}
