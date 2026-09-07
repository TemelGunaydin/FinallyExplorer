import Foundation
@testable import FinallyExplorer

nonisolated struct AskAISearchInterpreterStub: AskAISearchInterpreting {
    var respond: @Sendable (String, SmartSearchPlan?) async throws -> SmartSearchPlan = { _, _ in
        try SmartSearchTestFixtures.plan()
    }
    func interpret(_ query: String, previousPlan: SmartSearchPlan?) async throws -> SmartSearchPlan {
        try await respond(query, previousPlan)
    }
}

actor AskAISearchGate: AskAISearchInterpreting {
    private var continuation: CheckedContinuation<SmartSearchPlan, any Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var requested = false

    func interpret(_ query: String, previousPlan: SmartSearchPlan?) async throws -> SmartSearchPlan {
        try await withCheckedThrowingContinuation {
            continuation = $0
            requested = true
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func finish(_ plan: SmartSearchPlan) {
        continuation?.resume(returning: plan)
        continuation = nil
    }
}
