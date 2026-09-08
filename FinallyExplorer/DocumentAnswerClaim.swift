import Foundation

nonisolated struct DocumentAnswerClaim: Identifiable, Sendable {
    let id = UUID()
    let statement: String
    let quote: String
    let source: DocumentPassage
}
