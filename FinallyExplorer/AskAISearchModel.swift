import Foundation
import Observation

/// An explicit-submit, read-only conversation. Search results never become model instructions.
@MainActor
@Observable
final class AskAISearchModel {
    var draft = ""
    private(set) var turns: [AskAISearchTurn] = []
    private(set) var plan: SmartSearchPlan?
    private(set) var results: [ExplorerSearchResult] = []
    private(set) var message: ExplorerSearchMessage?
    private(set) var activity: String?
    private(set) var pendingRequest: String?
    private(set) var isEnabled = true

    @ObservationIgnored private let interpreter: any AskAISearchInterpreting
    @ObservationIgnored private let executor: any SmartSearchExecuting
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        interpreter: any AskAISearchInterpreting = FoundationModelsSmartSearchService(),
        executor: any SmartSearchExecuting = SpotlightSmartSearchService()
    ) {
        self.interpreter = interpreter
        self.executor = executor
    }

    deinit { task?.cancel() }

    var isWorking: Bool { activity != nil }
    var canSubmit: Bool {
        isEnabled && isWorking == false && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @discardableResult
    func submit(rootURL: URL) -> Task<Void, Never>? {
        guard canSubmit else { return nil }
        let query: String
        do { query = try SmartSearchRequestValidator.validatedQuery(draft) }
        catch {
            message = .error(error.localizedDescription)
            return nil
        }
        generation += 1
        let requestGeneration = generation
        let previousPlan = plan
        draft = ""
        pendingRequest = query
        message = nil
        activity = "Understanding your request…"
        task = Task { [weak self, interpreter, executor] in
            do {
                let nextPlan = try await interpreter.interpret(query, previousPlan: previousPlan)
                try Task.checkCancellation()
                guard self?.generation == requestGeneration else { return }
                self?.activity = "Searching indexed files…"
                let page = try await executor.search(rootURL: rootURL, plan: nextPlan)
                try Task.checkCancellation()
                guard let self, generation == requestGeneration else { return }
                plan = nextPlan
                results = page.results
                message = page.message
                let count = results.count == 1 ? "1 match" : "\(results.count) matches"
                appendTurn(request: query, response: "\(count) · \(nextPlan.filterLabels().joined(separator: " · "))", isError: false)
                activity = nil
                pendingRequest = nil
                task = nil
            } catch {
                guard let self, generation == requestGeneration else { return }
                if Task.isCancelled { cancel(); return }
                // Preserve the last successful plan and results, not a failed interpretation.
                let explanation = error.localizedDescription
                message = .error(explanation + (plan == nil ? "" : " Previous results and filters are unchanged."))
                appendTurn(request: query, response: explanation, isError: true)
                if draft.isEmpty { draft = query }
                activity = nil
                pendingRequest = nil
                task = nil
            }
        }
        return task
    }

    func cancel() {
        guard isWorking else { return }
        generation += 1
        task?.cancel()
        task = nil
        activity = nil
        if draft.isEmpty { draft = pendingRequest ?? "" }
        pendingRequest = nil
        message = .notice("Request cancelled. Previous results and filters are unchanged.")
    }

    func startNewSearch() {
        cancel()
        generation += 1
        draft = ""
        turns = []
        plan = nil
        results = []
        message = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled == false { startNewSearch() }
    }

    private func appendTurn(request: String, response: String, isError: Bool) {
        turns.append(AskAISearchTurn(request: request, response: response, isError: isError))
        if turns.count > 12 { turns.removeFirst(turns.count - 12) }
    }
}
