//
//  SearchTextMatchTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct SearchTextMatchTests {
    @Test("A contiguous filename match is highlighted as one range")
    func contiguousMatch() {
        let text = "ContentView.swift"
        let ranges = SearchTextMatch.ranges(in: text, matching: "view")

        #expect(ranges.map { String(text[$0]) } == ["View"])
    }

    @Test("A fuzzy filename match uses the tightest ordered window")
    func tightestFuzzyMatch() {
        let text = "v---p---w vPreview.swift"
        let ranges = SearchTextMatch.ranges(in: text, matching: "vpw")
        let tightestStart = text.range(of: "vPreview")?.lowerBound

        #expect(ranges.map { String(text[$0]) } == ["v", "P", "w"])
        #expect(ranges.first?.lowerBound == tightestStart)
    }

    @Test("Matching is case and diacritic insensitive")
    func normalizedMatch() {
        let text = "Résumé.PDF"
        let ranges = SearchTextMatch.ranges(in: text, matching: "resume")

        #expect(ranges.map { String(text[$0]) } == ["Résumé"])
    }

    @Test("Exact, prefix, contained, and fuzzy matches rank in that order")
    func matchQualityOrdering() throws {
        let exact = try #require(
            SearchTextMatch.match(in: "view", matching: "view")
        )
        let prefix = try #require(
            SearchTextMatch.match(in: "ViewModel.swift", matching: "view")
        )
        let contained = try #require(
            SearchTextMatch.match(in: "ContentView.swift", matching: "view")
        )
        let fuzzy = try #require(
            SearchTextMatch.match(in: "VideoPreview.swift", matching: "view")
        )

        #expect(exact.quality < prefix.quality)
        #expect(prefix.quality < contained.quality)
        #expect(contained.quality < fuzzy.quality)
    }

    @Test("Blank, impossible, and extended-grapheme queries are safe")
    func boundaryInputs() {
        #expect(SearchTextMatch.ranges(in: "file.swift", matching: "   ").isEmpty)
        #expect(SearchTextMatch.ranges(in: "abc", matching: "abcd").isEmpty)

        let text = "📁Project.swift"
        let ranges = SearchTextMatch.ranges(in: text, matching: "📁p")
        #expect(ranges.map { String(text[$0]) } == ["📁P"])
    }
}
