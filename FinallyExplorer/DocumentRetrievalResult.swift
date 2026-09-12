import Foundation

nonisolated struct DocumentRetrievalResult: Sendable {
    let passages: [DocumentPassage]
    let usedSemanticSearch: Bool
}
