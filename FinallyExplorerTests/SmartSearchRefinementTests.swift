import Foundation
import Testing
@testable import FinallyExplorer

struct SmartSearchRefinementTests {
    @Test("A type-only follow-up preserves keywords, location, and absolute dates across midnight")
    func preservesUnchangedFilters() throws {
        let previous = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(location: .downloads))
        let update = SmartSearchRefinement(mode: .refine, changedFilters: [.kind], search: SmartSearchTestFixtures.interpretation(
            keywords: [], kind: .pdf, location: .anywhere, dateRule: .none
        ))
        let refined = try update.resolve(previous: previous, now: SmartSearchTestFixtures.date("2026-09-06T12:00:00+03:00"), calendar: SmartSearchTestFixtures.calendar())
        #expect(refined.kind == .pdf)
        #expect(refined.keywords == previous.keywords)
        #expect(refined.location == .downloads)
        #expect(refined.dateInterval == previous.dateInterval)
        #expect(refined.area == previous.area)
    }

    @Test("An extension-only follow-up keeps the original capture-date meaning")
    func captureDateRefinement() throws {
        let previous = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: [], kind: .image, dateField: .captured))
        var search = SmartSearchTestFixtures.interpretation()
        search.fileExtensions = ["HEIC"]
        let result = try SmartSearchRefinement(mode: .refine, changedFilters: [.fileExtensions], search: search).resolve(
            previous: previous, now: .now, calendar: SmartSearchTestFixtures.calendar()
        )
        #expect(result.fileExtensions == ["heic"])
        #expect(result.kind == .image)
        #expect(result.dateField == .captured)
        #expect(result.dateInterval == previous.dateInterval)
    }

    @Test("A new search resets prior filters, while an unsupported follow-up is rejected")
    func newSearchAndUnsupported() throws {
        let previous = try SmartSearchTestFixtures.plan()
        var value = SmartSearchTestFixtures.interpretation(keywords: ["holiday"], kind: .image, dateRule: .none)
        let fresh = try SmartSearchRefinement(mode: .newSearch, changedFilters: [], search: value).resolve(previous: previous, now: .now, calendar: .current)
        #expect(fresh.keywords == ["holiday"])
        #expect(fresh.dateInterval == nil)
        value.unsupportedCriteria = ["Delete the results"]
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchRefinement(mode: .refine, changedFilters: [.kind], search: value).resolve(previous: previous, now: .now, calendar: .current)
        }
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchRefinement(mode: .refine, changedFilters: [], search: value).resolve(previous: previous, now: .now, calendar: .current)
        }
    }

    @Test("Extensions cannot inject wildcards or predicates", arguments: ["*", "jpg' OR TRUEPREDICATE", "../txt", ".pdf", "", "he ic"])
    func invalidExtensions(_ value: String) {
        var interpretation = SmartSearchTestFixtures.interpretation()
        interpretation.fileExtensions = [value]
        #expect(throws: SmartSearchError.invalidInterpretation) { try SmartSearchTestFixtures.plan(interpretation) }
    }

    @Test("Captured metadata is restricted to images")
    func rejectsCaptureDateForDocuments() {
        #expect(throws: SmartSearchError.unsupportedRequest) {
            try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(kind: .pdf, dateField: .captured))
        }
    }
}
