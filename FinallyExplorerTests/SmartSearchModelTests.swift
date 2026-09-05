import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct SmartSearchModelTests {
    private let root = URL(filePath: "/fixture", directoryHint: .isDirectory)

    @Test("Typing never invokes the model until Smart Search is submitted")
    func explicitSubmissionOnly() async throws {
        let normal = SmartSearchNormalServiceSpy()
        let interpreter = SmartSearchInterpreterStub { query in
            #expect(query == "Find the accounting report from 2 days ago")
            return try SmartSearchTestFixtures.plan()
        }
        let model = GlobalSearchModel(service: normal, initialRootURL: root,
                                      smartInterpreter: interpreter, smartService: SmartSearchExecutorStub())
        model.usesSmartSearch = true
        model.query = "Find the accounting report"
        await model.search(in: root)
        #expect(model.isAwaitingSmartSubmission)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(await normal.calls == 0)

        model.query = "Find the accounting report from 2 days ago"
        let before = model.request(in: root)
        model.submitSmartSearch()
        #expect(model.request(in: root) != before)
        await model.search(in: root)
        #expect(model.results == [SmartSearchTestFixtures.result(named: "accounting report.pdf")])
        #expect(model.highlightQuery == "accounting report")
        #expect(model.smartSearchPlan != nil)
        #expect(model.isSearching == false)
        #expect(model.isInterpretingSearch == false)
        #expect(await normal.calls == 0)
    }

    @Test("Ordinary name and grep searches do not invoke AI")
    func normalSearchRemainsIndependent() async {
        let normal = SmartSearchNormalServiceSpy()
        let interpreter = SmartSearchInterpreterStub { _ in
            Issue.record("Normal searches must not wait for or invoke Apple Intelligence.")
            throw SmartSearchError.interpretationFailed
        }
        let model = GlobalSearchModel(service: normal, initialRootURL: root, smartInterpreter: interpreter, debounce: {})
        model.query = "accounting"
        await model.search(in: root)
        model.scope = .contents
        model.contentMode = .regex
        await model.search(in: root)
        #expect(await normal.calls == 2)
        #expect(await normal.lastScope == .contents)
        #expect(await normal.lastContentMode == .regex)
    }

    @Test("Editing the sentence invalidates its old interpretation before file I/O")
    func rejectsLateInterpretation() async throws {
        let gate = SmartSearchInterpretationGate()
        let executor = SmartSearchExecutorStub { _, _ in
            Issue.record("An obsolete interpretation must not search for files.")
            return GlobalSearchPage(results: [], message: nil)
        }
        let model = GlobalSearchModel(initialRootURL: root, smartInterpreter: gate, smartService: executor)
        model.usesSmartSearch = true
        model.query = "old description"
        model.submitSmartSearch()
        let task = Task { await model.search(in: root) }
        await gate.waitUntilRequested()
        #expect(model.isInterpretingSearch)
        model.query = "new description"
        await gate.finish(with: try SmartSearchTestFixtures.plan())
        await task.value
        #expect(model.isAwaitingSmartSubmission)
        #expect(model.results.isEmpty)
        #expect(model.smartSearchPlan == nil)
        #expect(model.isInterpretingSearch == false)
    }

    @Test("Cancelling interpretation removes loading state without showing an error")
    func cancellation() async throws {
        let gate = SmartSearchInterpretationGate()
        let model = GlobalSearchModel(initialRootURL: root, smartInterpreter: gate, smartService: SmartSearchExecutorStub())
        model.usesSmartSearch = true
        model.query = "accounting report"
        model.submitSmartSearch()
        let task = Task { await model.search(in: root) }
        await gate.waitUntilRequested()
        task.cancel()
        await gate.finish(with: try SmartSearchTestFixtures.plan())
        await task.value
        #expect(model.isSearching == false)
        #expect(model.isInterpretingSearch == false)
        #expect(model.message == nil)
        #expect(model.results.isEmpty)
    }

    @Test("Unavailable AI produces a useful error and normal search still works")
    func unavailableModelDoesNotDisableSearch() async {
        let normal = SmartSearchNormalServiceSpy()
        let interpreter = SmartSearchInterpreterStub { _ in throw SmartSearchError.unavailable(.modelNotReady) }
        let model = GlobalSearchModel(service: normal, initialRootURL: root, smartInterpreter: interpreter)
        model.usesSmartSearch = true
        model.query = "report from yesterday"
        model.submitSmartSearch()
        await model.search(in: root)
        #expect(model.message?.isError == true)
        #expect(model.isSearching == false)
        #expect(model.isIndexReady(in: root))
        model.usesSmartSearch = false
        model.query = "report"
        await model.search(in: root)
        #expect(await normal.calls == 1)
        #expect(model.message == nil)
    }

    @Test("Turning Smart Search off in settings invalidates an in-flight interpretation")
    func disablingDuringSearch() async throws {
        let gate = SmartSearchInterpretationGate()
        let model = GlobalSearchModel(initialRootURL: root, smartInterpreter: gate, smartService: SmartSearchExecutorStub())
        model.usesSmartSearch = true
        model.query = "report"
        model.submitSmartSearch()
        let task = Task { await model.search(in: root) }
        await gate.waitUntilRequested()
        model.setSmartSearchAllowed(false)
        await gate.finish(with: try SmartSearchTestFixtures.plan())
        await task.value
        #expect(model.usesSmartSearch == false)
        #expect(model.smartSearchPlan == nil)
        #expect(model.results.isEmpty)
    }
}

private actor SmartSearchNormalServiceSpy: GlobalSearchServicing {
    private(set) var calls = 0
    private(set) var lastScope: ExplorerSearchScope?
    private(set) var lastContentMode: FFFContentSearchMode?
    func prepare(rootURL: URL) async throws {}
    func shutdown() async {}
    func search(rootURL: URL, query: String, scope: ExplorerSearchScope, contentMode: FFFContentSearchMode) async throws -> GlobalSearchPage {
        calls += 1
        lastScope = scope
        lastContentMode = contentMode
        return GlobalSearchPage(results: [], message: nil)
    }
}
