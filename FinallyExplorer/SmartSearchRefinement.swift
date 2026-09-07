import Foundation
import FoundationModels

/// The model identifies changes; code preserves every other validated filter.
@Generable
nonisolated struct SmartSearchRefinement: Sendable {
    @Guide(description: "refine for a follow-up such as only PDFs, last week instead, or in Documents instead. newSearch only for an explicitly new or unrelated search.")
    var mode: Mode

    @Guide(description: "Only filters explicitly replaced or removed by the latest request. All other filters are preserved by code. If replacing the file kind, also clear incompatible extensions using fileExtensions.", .maximumCount(6))
    var changedFilters: [Filter]

    @Guide(description: "Values for the changed filters, or the complete specification for a new search. Never omit unsupported requests: put them in unsupportedCriteria.")
    var search: SmartSearchInterpretation

    @Generable
    enum Mode: String, Sendable {
        case refine, newSearch
    }

    @Generable
    enum Filter: String, Hashable, Sendable {
        case keywords, area, kind, location, date, fileExtensions
    }

    func resolve(previous: SmartSearchPlan, now: Date, calendar: Calendar) throws -> SmartSearchPlan {
        if mode == .newSearch {
            return try SmartSearchPlan(interpretation: search, now: now, calendar: calendar)
        }
        guard changedFilters.isEmpty == false else { throw SmartSearchError.unsupportedRequest }
        return try SmartSearchPlan(refining: previous, with: self, now: now, calendar: calendar)
    }
}
