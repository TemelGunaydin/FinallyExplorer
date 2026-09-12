import Foundation

nonisolated enum DocumentFollowUpPolicy {
    /// Conservative guard before generation: a singular pronoun must not
    /// silently select the first item after an explicitly plural/list question.
    /// This is a narrow English guard, not a general ambiguity detector.
    static func requiresNamedSubject(question: String, context: [DocumentFollowUpContext]) -> Bool {
        let words = Set(question.lowercased().split { $0.isLetter == false }.map(String.init))
        guard words.isDisjoint(with: ["it", "its", "this", "that"]) == false,
              let previous = context.last?.question.lowercased() else { return false }
        if ["compare ", "list ", "what are ", "which are "].contains(where: previous.hasPrefix) { return true }
        let previousWords = previous.split { $0.isLetter == false }
        guard previousWords.first == "which", previousWords.count > 1 else { return false }
        let pluralSubjects: Set<String> = ["invoices", "documents", "files", "reports", "studios", "projects", "contracts",
            "accounts", "people", "vendors", "items", "payments", "companies", "customers", "employees", "orders", "policies"]
        return pluralSubjects.contains(String(previousWords[1]))
    }
}
