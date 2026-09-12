import Foundation

nonisolated struct QuestionDocument: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let parentState: ComparedFileState
    let state: ComparedFileState
    let passages: [DocumentPassage]
    let skippedPageCount: Int
    let ocrPageCount: Int
}
