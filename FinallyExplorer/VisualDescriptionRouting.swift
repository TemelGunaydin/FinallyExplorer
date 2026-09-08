import Foundation

nonisolated enum VisualDescriptionRouting {
    static func isVisualRequest(_ query: String) -> Bool {
        let text = query.lowercased()
        guard text.count <= 500,
              text.range(of: #"\b(photos?|pictures?|images?)\b"#, options: .regularExpression) != nil,
              text.range(of: #"\b(names?|named|filenames?|called)\b"#, options: .regularExpression) == nil else { return false }
        return text.range(of: #"\b(depicting|showing|containing|of|with|near|by|at)\b|\b(beach|seaside|sea|ocean|coast|mountains?|cats?|dogs?|sunset|forest|snow)\b"#, options: .regularExpression) != nil
    }

    /// Exact common sentences are fast even without Apple Intelligence. Do not
    /// strip arbitrary words: that would silently discard dates or exclusions.
    static func quickPlan(_ query: String) throws -> VisualDescriptionPlan? {
        let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:(?:find|show)(?: me)? )?(?:my |the )?(?:photos?|pictures?|images?)(?: (?:taken|shot|captured))? (?:at|by|near|of|depicting|showing) (?:the )?(?:sea|seaside|beach|coast|ocean)[.!?]?$|^(?:(?:find|show)(?: me)? )?(?:my |the )?(?:beach|seaside|coastal) (?:photos?|pictures?|images?)[.!?]?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return try VisualDescriptionPlan(concepts: [["beach", "seashore", "coast", "coastal", "ocean", "sea"]])
    }
}
