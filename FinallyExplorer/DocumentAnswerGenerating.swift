import Foundation

nonisolated protocol DocumentAnswerGenerating: Sendable {
    func answer(question: String, sources: [DocumentPassage]) async throws -> DocumentAnswerDraft
}
