import Foundation
@testable import FinallyExplorer

actor RecordingDocumentResolver: DocumentQuestionResolving {
    private(set) var contexts: [[DocumentFollowUpContext]] = []
    var result: String
    let gate: FolderComparisonTestGate?
    let error: DocumentQuestionError?
    init(result: String, gate: FolderComparisonTestGate? = nil, error: DocumentQuestionError? = nil) {
        self.result = result; self.gate = gate; self.error = error
    }
    func resolve(question: String, context: [DocumentFollowUpContext]) async throws -> String {
        contexts.append(context)
        if let gate { await gate.pause() }
        if let error { throw error }
        return result
    }
}

actor RecordingDocumentAnswerer: DocumentAnswerGenerating {
    private(set) var questions: [String] = []
    func answer(question: String, sources: [DocumentPassage]) async throws -> DocumentAnswerDraft {
        questions.append(question)
        return try await QuotingDocumentAnswerer().answer(question: question, sources: sources)
    }
}

nonisolated struct PausedDocumentSemanticEncoder: DocumentSemanticEncoding {
    let gate: FolderComparisonTestGate
    func vectors(for texts: [String]) async throws -> [[Double]]? {
        await gate.pause()
        return nil
    }
}
