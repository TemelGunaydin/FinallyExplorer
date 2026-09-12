import Foundation
@testable import FinallyExplorer

actor RecordingDocumentEncoder: DocumentSemanticEncoding {
    private(set) var batches: [[String]] = []
    let omitQuery: Bool
    let queryGate: FolderComparisonTestGate?
    init(omitQuery: Bool = false, queryGate: FolderComparisonTestGate? = nil) {
        self.omitQuery = omitQuery; self.queryGate = queryGate
    }
    func vectors(for texts: [String]) async throws -> [[Double]]? {
        batches.append(texts)
        if batches.count > 1 {
            if let queryGate { await queryGate.pause() }
            if omitQuery { return nil }
        }
        return texts.map { _ in [1, 0] }
    }
}

nonisolated struct MalformedDocumentEncoder: DocumentSemanticEncoding {
    func vectors(for texts: [String]) async throws -> [[Double]]? {
        texts.map { _ in [Double.nan, 0] }
    }
}
