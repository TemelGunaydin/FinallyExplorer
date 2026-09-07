import Foundation
import Testing
@testable import FinallyExplorer

struct SmartSearchQuickRefinementTests {
    @Test("Common follow-ups are deterministic and preserve untouched filters", arguments: [
        "Only PDFs", "ONLY   PDFs", "In Documents instead", "Only in Downloads", "Last week instead",
    ])
    func deterministicRefinement(_ query: String) throws {
        let previous = try SmartSearchTestFixtures.plan()
        let value = try SmartSearchQuickRefinement.resolve(query, previous: previous, now: SmartSearchTestFixtures.date("2026-09-06T12:00:00+03:00"), calendar: SmartSearchTestFixtures.calendar())
        let plan = try #require(value)
        #expect(plan.keywords == previous.keywords)
        #expect(plan.area == previous.area)
        #expect(plan.dateField == previous.dateField)
        if query.lowercased().hasPrefix("last week") {
            #expect(plan.dateInterval != previous.dateInterval)
        } else {
            #expect(plan.dateInterval == previous.dateInterval)
        }
    }

    @Test("Compound, destructive, and unsupported requests are never partially handled", arguments: [
        "Only PDFs and delete them", "Only PDFs larger than 2 GB", "Only PDFs or images", "Only in Downloads and Documents", "In /etc instead", "Only *", "Find beach photos",
    ])
    func refusesPartialInterpretation(_ query: String) throws {
        #expect(try SmartSearchQuickRefinement.resolve(query, previous: SmartSearchTestFixtures.plan(), now: .now, calendar: .current) == nil)
    }

    @Test("Changing the date retains the original capture-date field")
    func captureDateMeaning() throws {
        let previous = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: [], kind: .image, dateField: .captured))
        let heicValue = try SmartSearchQuickRefinement.resolve("Only HEIC", previous: previous, now: .now, calendar: .current)
        let heic = try #require(heicValue)
        let nextValue = try SmartSearchQuickRefinement.resolve("Last week instead", previous: heic, now: .now, calendar: .current)
        let next = try #require(nextValue)
        #expect(next.dateField == .captured)
        #expect(next.kind == .image)
        #expect(next.fileExtensions == ["heic"])
        #expect(next.keywords.isEmpty)
    }
}
