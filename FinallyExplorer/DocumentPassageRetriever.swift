import Foundation

nonisolated enum DocumentPassageRetriever {
    @concurrent static func retrieve(question: String, documents: [QuestionDocument]) async throws -> [DocumentPassage] {
        let ignored: Set<String> = ["a", "an", "the", "is", "are", "was", "were", "what", "when", "where", "why", "how", "which", "who", "does", "do", "did", "can", "could", "would", "will", "should", "of", "to", "in", "on", "for", "from", "by", "with", "about", "it", "its", "this", "that", "these", "those", "my", "me", "i", "we", "our", "you", "your", "and", "or", "please", "tell", "document", "documents", "file", "files", "say", "says"]
        let tokens = Set(question.lowercased().split(whereSeparator: { $0.isLetter == false && $0.isNumber == false }).map(String.init)).subtracting(ignored)
        guard tokens.isEmpty == false else { throw DocumentQuestionError.noEvidence }
        var scored: [(DocumentPassage, Int)] = []
        for passage in documents.flatMap(\.passages) {
            try Task.checkCancellation()
            let words = Set(passage.text.lowercased().split(whereSeparator: { $0.isLetter == false && $0.isNumber == false }).map(String.init))
            let score = tokens.intersection(words).count
            if score > 0 { scored.append((passage, score)) }
        }
        let ranked = scored.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        // Four small excerpts leave headroom for instructions/schema/output on
        // the macOS 26 model. Count bytes, not characters, for multilingual input.
        return ranked.prefix(4).map { passage, _ in
            let text = passage.text
            let firstMatch = tokens.compactMap { text.range(of: $0, options: .caseInsensitive)?.lowerBound }.min() ?? text.startIndex
            let start = text.index(firstMatch, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
            var excerpt = "", bytes = 0
            for character in text[start...] {
                let count = String(character).utf8.count
                if bytes + count > 600 { break }
                excerpt.append(character); bytes += count
            }
            return DocumentPassage(id: passage.id, documentID: passage.documentID, fileName: passage.fileName, page: passage.page, text: excerpt)
        }
    }
}
