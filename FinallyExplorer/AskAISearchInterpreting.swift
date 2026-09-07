import Foundation

nonisolated protocol AskAISearchInterpreting: Sendable {
    func interpret(_ query: String, previousPlan: SmartSearchPlan?) async throws -> SmartSearchPlan
}
