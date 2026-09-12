import FoundationModels

@Generable
nonisolated struct DocumentFollowUpDraft {
    @Guide(description: "The current question as one self-contained English question, at most 500 characters. Never answer it. Empty when clarification is needed.")
    var question: String
    @Guide(description: "True only if the subject remains ambiguous. A new explicitly named subject does not need to have appeared in history.")
    var needsClarification: Bool
}
