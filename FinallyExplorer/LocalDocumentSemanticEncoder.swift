import NaturalLanguage

nonisolated struct LocalDocumentSemanticEncoder: DocumentSemanticEncoding {
    @concurrent func vectors(for texts: [String]) async throws -> [[Double]]? {
        try Task.checkCancellation()
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        // NLEmbedding is not thread-safe. This instance belongs to this one
        // invocation, with serial, synchronous queries and no shared model.
        var result: [[Double]] = []
        for text in texts {
            try Task.checkCancellation()
            guard let vector = embedding.vector(for: text),
                  vector.isEmpty == false, vector.allSatisfy(\.isFinite) else { return nil }
            let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
            guard length.isFinite, length > 0 else { return nil }
            result.append(vector.map { $0 / length })
        }
        try Task.checkCancellation()
        return result
    }
}
