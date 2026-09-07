import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct AskAISearchModelTests {
    private let root = URL(filePath: "/fixture")

    @Test("Typing does not infer; submitting searches once with the resolved plan")
    func explicitSubmission() async throws {
        let plan = try SmartSearchTestFixtures.plan()
        let model = AskAISearchModel(interpreter: AskAISearchInterpreterStub { query, previous in
            #expect(query == "Find accounting reports")
            #expect(previous == nil)
            return plan
        }, executor: SmartSearchExecutorStub())
        model.draft = "Find accounting reports"
        #expect(model.plan == nil)
        #expect(model.turns.isEmpty)
        #expect(model.isWorking == false)
        let task = try #require(model.submit(rootURL: root))
        await task.value
        #expect(model.plan == plan)
        #expect(model.results.count == 1)
        #expect(model.turns.count == 1)
        #expect(model.draft.isEmpty)
        #expect(model.isWorking == false)
    }

    @Test("A failed follow-up preserves the last successful context and labels its results")
    func failurePreservesContext() async throws {
        let plan = try SmartSearchTestFixtures.plan()
        let model = AskAISearchModel(interpreter: AskAISearchInterpreterStub { query, previous in
            if query == "first" { #expect(previous == nil); return plan }
            #expect(previous == plan)
            if query == "unsupported" { throw SmartSearchError.unsupportedRequest }
            return plan
        }, executor: SmartSearchExecutorStub())
        model.draft = "first"
        await model.submit(rootURL: root)?.value
        model.draft = "unsupported"
        await model.submit(rootURL: root)?.value
        #expect(model.plan == plan)
        #expect(model.results.count == 1)
        #expect(model.message?.text.contains("unchanged") == true)
        #expect(model.turns.last?.isError == true)
        model.draft = "retry"
        await model.submit(rootURL: root)?.value
        #expect(model.turns.last?.isError == false)
        #expect(model.message == nil)
    }

    @Test("Clearing or disabling the panel cannot be undone by a late inference", arguments: [true, false])
    func staleCompletion(_ disable: Bool) async throws {
        let gate = AskAISearchGate()
        let model = AskAISearchModel(interpreter: gate, executor: SmartSearchExecutorStub { _, _ in
            Issue.record("A cancelled interpretation must not execute a search")
            return GlobalSearchPage(results: [], message: nil)
        })
        model.draft = "first"
        let task = try #require(model.submit(rootURL: root))
        await gate.waitUntilRequested()
        if disable { model.setEnabled(false) } else { model.startNewSearch() }
        await gate.finish(try SmartSearchTestFixtures.plan())
        await task.value
        #expect(model.plan == nil)
        #expect(model.results.isEmpty)
        #expect(model.turns.isEmpty)
        #expect(model.isWorking == false)
        #expect(model.message == nil)
    }

    @Test("Invalid or disabled submissions never reach the model")
    func validationAndOptOut() {
        let model = AskAISearchModel(interpreter: AskAISearchInterpreterStub { _, _ in
            Issue.record("Input should be rejected before inference")
            throw SmartSearchError.invalidRequest
        })
        model.draft = String(repeating: "x", count: 501)
        #expect(model.submit(rootURL: root) == nil)
        #expect(model.message?.isError == true)
        model.setEnabled(false)
        model.draft = "Find reports"
        #expect(model.canSubmit == false)
        #expect(model.submit(rootURL: root) == nil)
    }

    @Test("Cancel restores the request and cannot publish late results")
    func cancelRequest() async throws {
        let gate = AskAISearchGate()
        let model = AskAISearchModel(interpreter: gate, executor: SmartSearchExecutorStub())
        model.draft = "Find reports"
        let task = try #require(model.submit(rootURL: root))
        await gate.waitUntilRequested()
        #expect(model.pendingRequest == "Find reports")
        #expect(model.submit(rootURL: root) == nil)
        model.cancel()
        await gate.finish(try SmartSearchTestFixtures.plan())
        await task.value
        #expect(model.draft == "Find reports")
        #expect(model.pendingRequest == nil)
        #expect(model.results.isEmpty)
        #expect(model.isWorking == false)
    }

    @Test("New Search clears context and conversation history stays bounded")
    func resetAndHistoryLimit() async throws {
        let model = AskAISearchModel(interpreter: AskAISearchInterpreterStub(), executor: SmartSearchExecutorStub())
        for index in 0..<15 {
            model.draft = "Request \(index)"
            await model.submit(rootURL: root)?.value
        }
        #expect(model.turns.count == 12)
        #expect(model.turns.first?.request == "Request 3")
        model.startNewSearch()
        #expect(model.plan == nil)
        #expect(model.results.isEmpty)
        #expect(model.turns.isEmpty)
    }
}
