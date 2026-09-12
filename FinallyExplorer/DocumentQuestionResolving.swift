import Foundation

nonisolated protocol DocumentQuestionResolving: Sendable {
    func resolve(question: String, context: [DocumentFollowUpContext]) async throws -> String
}
