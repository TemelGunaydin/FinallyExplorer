import Foundation

nonisolated struct DocumentFollowUpContext: Encodable, Sendable {
    let question: String
    let supportingQuotes: [String]

    init(turn: DocumentQuestionTurn) {
        question = turn.resolvedQuestion
        // Generated statements are deliberately not conversational evidence.
        // Only quotes already verified against this selection enter context.
        supportingQuotes = turn.claims.prefix(2).map {
            LocalDocumentPassageSearch.bytePrefix($0.quote[...], limit: 300)
        }
    }
}
