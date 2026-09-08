import Foundation

nonisolated enum DocumentAnswerValidator {
    static func validate(_ draft: DocumentAnswerDraft, sources: [DocumentPassage]) throws -> [DocumentAnswerClaim] {
        if draft.insufficientEvidence { throw DocumentQuestionError.noEvidence }
        guard (1...3).contains(draft.claims.count) else { throw DocumentQuestionError.invalidAnswer }
        return try draft.claims.map { claim in
            let quote = LocalDocumentReader.normalized(claim.quote)
            let statement = claim.statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (8...300).contains(quote.count), (1...600).contains(statement.count),
                  let source = sources.first(where: { $0.id == claim.sourceID }),
                  source.text.contains(quote) else { throw DocumentQuestionError.invalidAnswer }
            return DocumentAnswerClaim(statement: statement, quote: quote, source: source)
        }
    }
}
