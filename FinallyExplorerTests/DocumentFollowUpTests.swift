import Foundation
import Testing
@testable import FinallyExplorer

@MainActor struct DocumentFollowUpTests {
    private let initial = "When is Harbor Studio's invoice due?"
    private let resolved = "When was Harbor Studio's invoice issued?"

    private func ready(_ fixture: FolderComparisonTestFixture, resolver: any DocumentQuestionResolving,
                       answerer: any DocumentAnswerGenerating = QuotingDocumentAnswerer()) async throws -> DocumentQuestionModel {
        let file = try fixture.write("Harbor.txt", "Harbor Studio invoice 4827 was issued on 2 September 2026. Payment is due on 30 September 2026.")
        let model = DocumentQuestionModel(answerer: answerer, resolver: resolver,
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select([file]); await model.readDocuments()?.value
        model.question = initial; await model.ask()?.value
        try #require(model.errorMessage == nil)
        try #require(model.history.count == 1)
        return model
    }

    @Test("Follow-ups retrieve fresh sources for a self-contained question, not generated answer text")
    func contextAndResolution() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let resolver = RecordingDocumentResolver(result: resolved)
        let answerer = RecordingDocumentAnswerer()
        let model = try await ready(fixture, resolver: resolver, answerer: answerer)
        #expect(await resolver.contexts.isEmpty)
        model.question = "When was it issued?"; await model.ask()?.value
        #expect(model.errorMessage == nil)
        #expect(model.history.count == 2)
        #expect(model.answeredQuestion == "When was it issued?")
        #expect(model.resolvedQuestion == resolved)
        #expect(model.history.last?.resolvedQuestion == resolved)
        #expect(await answerer.questions == [initial, resolved])
        let context = try #require(await resolver.contexts.first?.first)
        #expect(context.question == initial)
        #expect(context.supportingQuotes == model.history[0].claims.map(\.quote))
        #expect(context.supportingQuotes.contains { $0.contains("The document states") } == false)
    }

    @Test("Conversation history is bounded; New Conversation keeps prepared documents without old context")
    func boundedHistoryAndReset() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let resolver = RecordingDocumentResolver(result: resolved)
        let model = try await ready(fixture, resolver: resolver)
        for number in 1...5 { model.question = "Follow-up \(number)"; await model.ask()?.value }
        #expect(model.history.count == 3)
        #expect(model.history.first?.question == "Follow-up 3")
        #expect(await resolver.contexts.map(\.count) == [1, 2, 2, 2, 2])
        let documentIDs = model.documents.map(\.id)
        model.newConversation()
        #expect(model.history.isEmpty)
        #expect(model.claims.isEmpty && model.passages.isEmpty)
        #expect(model.resolvedQuestion == nil && model.question.isEmpty)
        #expect(model.documents.map(\.id) == documentIDs)
        #expect(model.retrievalIndex != nil)
        model.question = initial; await model.ask()?.value
        #expect(model.history.count == 1)
        #expect(await resolver.contexts.count == 5, "A fresh question must not call the follow-up resolver")
        model.select(model.selection)
        #expect(model.history.isEmpty && model.documents.isEmpty)
        #expect(model.retrievalIndex == nil)
    }

    @Test("Follow-up context includes only two byte-bounded source quotes, preserving Unicode")
    func contextQuoteBudget() {
        let quote = String(repeating: "🌅", count: 150)
        let source = DocumentPassage(id: 1, documentID: UUID(), fileName: "Note.txt", page: nil, text: quote)
        let claims = (0..<3).map { number in
            DocumentAnswerClaim(statement: "Generated statement \(number)", quote: quote, source: source)
        }
        let context = DocumentFollowUpContext(turn: DocumentQuestionTurn(
            question: "When was it issued?", resolvedQuestion: resolved, claims: claims))
        #expect(context.question == resolved)
        #expect(context.supportingQuotes.count == 2)
        #expect(context.supportingQuotes.allSatisfy { $0.utf8.count == 300 })
        #expect(context.supportingQuotes.allSatisfy { quote.hasPrefix($0) })
        #expect(context.supportingQuotes.allSatisfy { $0 == String(repeating: "🌅", count: 75) })
    }

    @Test("Ambiguous or overlong resolutions leave the last verified answer intact", arguments: [false, true])
    func invalidFollowUp(_ overlong: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let resolver = RecordingDocumentResolver(result: String(repeating: "a", count: 501),
            error: overlong ? nil : .ambiguousFollowUp)
        let answerer = RecordingDocumentAnswerer()
        let model = try await ready(fixture, resolver: resolver, answerer: answerer)
        let previous = model.history[0].id
        model.question = "When was it issued?"; await model.ask()?.value
        #expect(model.errorMessage == DocumentQuestionError.ambiguousFollowUp.localizedDescription)
        #expect(model.history.map(\.id) == [previous])
        #expect(model.answeredQuestion == initial)
        #expect(await answerer.questions == [initial])
    }

    @Test("Cancellation during follow-up resolution never restores cleared context", .timeLimit(.minutes(1)), arguments: ["new", "clear", "optOut"])
    func cancelResolution(_ action: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let gate = FolderComparisonTestGate()
        let resolver = RecordingDocumentResolver(result: resolved, gate: gate)
        let model = try await ready(fixture, resolver: resolver)
        model.question = "When was it issued?"
        let work = try #require(model.ask())
        await gate.waitUntilEntered()
        switch action {
        case "new": model.newConversation()
        case "clear": model.clear()
        default: model.setEnabled(false)
        }
        #expect(model.isWorking && model.isCancelling)
        #expect(model.ask() == nil)
        await gate.release(); await work.value
        #expect(model.isWorking == false)
        #expect(model.history.isEmpty && model.claims.isEmpty && model.passages.isEmpty)
        #expect(model.errorMessage == nil)
        #expect((model.retrievalIndex != nil) == (action == "new"))
    }

    @Test("Sources changed during follow-up resolution invalidate conversation and index", .timeLimit(.minutes(1)))
    func changedSource() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let gate = FolderComparisonTestGate()
        let resolver = RecordingDocumentResolver(result: resolved, gate: gate)
        let answerer = RecordingDocumentAnswerer()
        let model = try await ready(fixture, resolver: resolver, answerer: answerer)
        let file = try #require(model.selection.first)
        model.question = "When was it issued?"
        let work = try #require(model.ask())
        await gate.waitUntilEntered()
        try Data("Changed invoice".utf8).write(to: file)
        await gate.release(); await work.value
        #expect(model.errorMessage == DocumentQuestionError.changed.localizedDescription)
        #expect(model.history.isEmpty && model.documents.isEmpty)
        #expect(model.retrievalIndex == nil)
        #expect(await answerer.questions == [initial])
    }

    @Test("Clearing during embedding preparation discards the text and prepared vectors", .timeLimit(.minutes(1)))
    func cancelPreparation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Policy.txt", "The payment deadline is Friday.")
        let gate = FolderComparisonTestGate()
        let model = DocumentQuestionModel(search: LocalDocumentPassageSearch(encoder: PausedDocumentSemanticEncoder(gate: gate)))
        model.select([file])
        let work = try #require(model.readDocuments())
        await gate.waitUntilEntered()
        model.clear()
        #expect(model.isWorking)
        await gate.release(); await work.value
        #expect(model.documents.isEmpty && model.retrievalIndex == nil)
        #expect(model.isWorking == false)
    }
}
