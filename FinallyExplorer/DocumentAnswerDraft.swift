import FoundationModels

@Generable
nonisolated struct DocumentAnswerDraft {
    @Guide(description: "True if the excerpts do not contain the answer. Never guess from general knowledge.")
    var insufficientEvidence: Bool
    @Guide(description: "Up to three short answer statements, each with its own supporting source and exact quote. Empty if evidence is insufficient.", .maximumCount(3))
    var claims: [DocumentAnswerClaimDraft]
}
