import FoundationModels

@Generable
nonisolated struct DocumentAnswerClaimDraft {
    @Guide(description: "One concise factual answer statement, supported entirely by the quoted excerpt.")
    var statement: String
    @Guide(description: "Exact integer source ID from the provided excerpts.")
    var sourceID: Int
    @Guide(description: "Copy an exact, contiguous supporting quote from this source, 8 to 300 characters. Never invent or paraphrase a quote.")
    var quote: String
}
