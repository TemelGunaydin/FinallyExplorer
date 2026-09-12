import Foundation

/// Prepared only after explicit reading; retained in the window's memory.
nonisolated struct DocumentRetrievalIndex: Sendable {
    let excerpts: [DocumentPassage]
    let words: [Set<String>]
    let vectors: [[Double]]?
    var supportsSemanticSearch: Bool { vectors != nil }
}
