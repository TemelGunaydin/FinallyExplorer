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
        // The small language model can silently drop conditions it cannot
        // express. Reject common unsupported criteria before inference too.
        let unsupported = [
            #"\b(?:larger|smaller|bigger|over|under|at least|at most|more than|less than)\b.*\b\d+(?:[.,]\d+)?\s*(?:bytes?|[kmgt]i?b)\b"#,
            #"\b(?:downloaded|imported|received)\s+(?:(?:from|on|in|within|during|the|last|this)\s+)*(?:today|yesterday|\d+|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year)\b"#,
        ]
        if unsupported.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
            throw SmartSearchError.unsupportedRequest
        }
        let visualSubject = #"\b(?:photos?|pictures?|images?)\s+(?:depicting|showing|of|with)\b"#
        if explicitlySearchesNames(text) == false,
           text.range(of: visualSubject, options: [.regularExpression, .caseInsensitive]) != nil {
            throw SmartSearchError.unsupportedRequest
        }
        return text
    }

    static func validateCapabilities(_ plan: SmartSearchPlan, query: String, previousPlan: SmartSearchPlan? = nil) throws {
        // Image subjects need a visual index, which is not implemented. A name
        // query must be explicit; never masquerade keyword matches as vision.
        if plan.kind == .image, plan.keywords.isEmpty == false {
            let inheritsValidatedKeywords = previousPlan?.kind == .image
                && previousPlan?.keywords == plan.keywords && previousPlan?.area == plan.area
            guard explicitlySearchesNames(query) || inheritsValidatedKeywords else {
                throw SmartSearchError.unsupportedRequest
            }
        }
    }

    static func removingRedundantTypeWords(_ value: SmartSearchInterpretation, query: String) -> SmartSearchInterpretation {
        guard explicitlySearchesNames(query) == false else { return value }
        let redundant: Set<String> = switch value.kind {
        case .image: ["photo", "photos", "image", "images", "picture", "pictures"]
        case .pdf: ["pdf", "pdfs"]
        case .video: ["video", "videos"]
        case .folder: ["folder", "folders"]
        default: []
        }
        var result = value
        // The selected kind already represents these generic words. Keep all
        // topic terms (including report/invoice), and every explicit filename.
        result.keywords.removeAll { redundant.contains($0.lowercased()) }
        return result
    }

    private static func explicitlySearchesNames(_ query: String) -> Bool {
        query.range(of: #"\b(?:name|names|named|filename|filenames|called)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
