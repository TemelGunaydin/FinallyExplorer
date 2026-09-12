import Foundation

nonisolated struct LocalDocumentPassageSearch: Sendable {
    var encoder: any DocumentSemanticEncoding = LocalDocumentSemanticEncoder()

    @concurrent func prepare(_ documents: [QuestionDocument]) async throws -> DocumentRetrievalIndex {
        var excerpts: [DocumentPassage] = []
        for passage in documents.flatMap(\.passages) {
            try Task.checkCancellation()
            // Embed exactly what can later be cited, including text near the
            // end of a long passage. Every window remains a contiguous quote.
            var start = passage.text.startIndex
            while start < passage.text.endIndex {
                let text = Self.bytePrefix(passage.text[start...], limit: 600)
                guard text.isEmpty == false else { break }
                excerpts.append(DocumentPassage(id: passage.id, documentID: passage.documentID,
                    fileName: passage.fileName, page: passage.page, text: text, isOCR: passage.isOCR))
                let end = passage.text.index(start, offsetBy: text.count)
                guard end < passage.text.endIndex else { break }
                start = passage.text.index(end, offsetBy: -min(60, text.count / 3))
            }
        }
        let vectors = try await encoder.vectors(for: excerpts.map(\.text))
        try Task.checkCancellation()
        return DocumentRetrievalIndex(excerpts: excerpts, words: excerpts.map { Self.tokens($0.text) },
            vectors: Self.validVectors(vectors, count: excerpts.count))
    }

    @concurrent func retrieve(question: String, index: DocumentRetrievalIndex) async throws -> DocumentRetrievalResult {
        try Task.checkCancellation()
        let queryWords = Self.tokens(question)
        guard queryWords.isEmpty == false else { throw DocumentQuestionError.noEvidence }
        let queryVector: [Double]?
        if index.supportsSemanticSearch {
            queryVector = Self.validVectors(try await encoder.vectors(for: [question]), count: 1)?.first
        } else { queryVector = nil }
        try Task.checkCancellation()
        let usesSemantics = queryVector?.count == index.vectors?.first?.count && queryVector != nil
        // Rare names/identifiers matter as well as meaning; semantic similarity
        // alone must not replace a specifically requested invoice or person.
        let weights = queryWords.map { word in
            (word, 1 + log(Double(index.words.count + 1) / Double(index.words.filter { $0.contains(word) }.count + 1)))
        }
        let totalWeight = weights.reduce(0) { $0 + $1.1 }
        var scored: [(Int, Double)] = []
        for offset in index.excerpts.indices {
            try Task.checkCancellation()
            let lexical = weights.reduce(0) { $0 + (index.words[offset].contains($1.0) ? $1.1 : 0) } / totalWeight
            var similarity = 0.0
            if usesSemantics, let queryVector, let vectors = index.vectors {
                similarity = zip(queryVector, vectors[offset]).reduce(0) { $0 + $1.0 * $1.1 }
            }
            // Similarity is a retrieval heuristic, never a confidence score or
            // proof of an answer. Exact source verification still follows.
            if lexical > 0 || similarity >= 0.22 {
                scored.append((offset, lexical + 0.65 * max(0, similarity)))
            }
        }
        scored.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        var selected: [DocumentPassage] = []
        for (offset, _) in scored {
            let passage = index.excerpts[offset]
            // Overlapping windows must not consume the whole model budget.
            guard selected.contains(where: { $0.id == passage.id ||
                ($0.documentID == passage.documentID && $0.page == passage.page && $0.text == passage.text)
            }) == false else { continue }
            selected.append(passage)
            if selected.count == 4 { break }
        }
        return DocumentRetrievalResult(passages: selected, usedSemanticSearch: usesSemantics)
    }

    static func bytePrefix(_ text: Substring, limit: Int) -> String {
        var result = "", bytes = 0
        for character in text {
            let count = String(character).utf8.count
            guard bytes + count <= limit else { break }
            result.append(character); bytes += count
        }
        return result
    }

    private static func validVectors(_ vectors: [[Double]]?, count: Int) -> [[Double]]? {
        guard let vectors, vectors.count == count, let dimension = vectors.first?.count, dimension > 0,
              vectors.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) }) else { return nil }
        return vectors
    }

    private static let ignored: Set<String> = ["a", "an", "the", "is", "are", "was", "were", "what", "when", "where", "why", "how", "which", "who", "does", "do", "did", "can", "could", "would", "will", "should", "of", "to", "in", "on", "for", "from", "by", "with", "about", "it", "its", "this", "that", "these", "those", "my", "me", "i", "we", "our", "you", "your", "and", "or", "please", "tell", "document", "documents", "file", "files", "say", "says"]

    private static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { $0.isLetter == false && $0.isNumber == false }).map(String.init)).subtracting(ignored)
    }
}
