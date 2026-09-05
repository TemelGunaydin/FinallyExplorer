import Foundation

nonisolated enum SmartSearchRequestValidator {
    static func validatedQuery(_ query: String) throws -> String {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, text.count <= 500,
              text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) == false else {
            throw SmartSearchError.invalidRequest
        }
        // This feature is a file lookup, not an action agent. Do not rely on an
        // LLM to distinguish an imperative from a request to find matching files.
        let action = #"^(?:(?:please|can you|could you|would you)\s+)*(?:delete|remove|trash|erase|move|copy|rename|zip|compress|uninstall|execute|run|open)\b"#
        if text.range(of: action, options: [.regularExpression, .caseInsensitive]) != nil {
            throw SmartSearchError.unsupportedRequest
        }
        return text
    }
}
