import Foundation
import Testing
@testable import FinallyExplorer

struct SmartSearchPredicateBuilderTests {
    @Test("Date filtering includes midnight but excludes the next day")
    func halfOpenDateBoundaries() throws {
        let plan = try SmartSearchTestFixtures.plan()
        let interval = try #require(plan.dateInterval)
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        func matches(_ date: Date) -> Bool {
            predicate.evaluate(with: [
                NSMetadataItemFSNameKey: "accounting report.pdf",
                NSMetadataItemContentModificationDateKey: date,
            ])
        }
        #expect(matches(interval.start))
        #expect(matches(interval.end.addingTimeInterval(-1)))
        #expect(matches(interval.start.addingTimeInterval(-1)) == false)
        #expect(matches(interval.end) == false)
    }

    @Test("A report can match indexed content even when its name is scan.pdf", arguments: [
        (SmartSearchInterpretation.Area.namesAndContents, true), (.contents, true), (.names, false),
    ])
    func indexedContentMatch(_ area: SmartSearchInterpretation.Area, _ expected: Bool) throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(area: area, dateRule: .none))
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        #expect(predicate.evaluate(with: [
            NSMetadataItemFSNameKey: "scan.pdf",
            NSMetadataItemTextContentKey: "The accounting report for this month.",
        ]) == expected)
        #expect(predicate.evaluate(with: [
            NSMetadataItemFSNameKey: "unrelated.txt",
            NSMetadataItemTextContentKey: "Only an accounting reference; no second term.",
        ]) == false)
    }

    @Test("Created-date requests do not accidentally use modification date")
    func creationDateIsSeparate() throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(dateField: .created))
        let interval = try #require(plan.dateInterval)
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        #expect(predicate.evaluate(with: [
            NSMetadataItemFSNameKey: "accounting report.pdf",
            "kMDItemFSCreationDate": interval.start,
            NSMetadataItemContentModificationDateKey: interval.end,
        ]))
        #expect(predicate.evaluate(with: [
            NSMetadataItemFSNameKey: "accounting report.pdf",
            "kMDItemFSCreationDate": interval.end,
            NSMetadataItemContentModificationDateKey: interval.start,
        ]) == false)
    }

    @Test("Untrusted terms cannot become predicate syntax")
    func predicateInjectionRemainsLiteral() throws {
        let term = "report' OR TRUEPREDICATE"
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(
            keywords: [term], area: .names, dateRule: .none
        ))
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        #expect(predicate is NSCompoundPredicate == false)
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: "other.pdf"]) == false)
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: term + ".txt"]))
    }

    @Test("Extension-only filters are case-insensitive and accepted by Spotlight")
    func extensionPredicate() throws {
        var interpretation = SmartSearchTestFixtures.interpretation(keywords: [], dateRule: .none)
        interpretation.fileExtensions = ["HEIC"]
        let predicate = SmartSearchPredicateBuilder.predicate(for: try SmartSearchTestFixtures.plan(interpretation))
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: "IMG_1.heic"]))
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: "IMG_1.HEIC"]))
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: "IMG_1.jpg"]) == false)
        let query = NSMetadataQuery()
        query.predicate = predicate
        #expect(query.predicate != nil)
    }

    @Test("Capture-date candidate predicates use content creation, not filesystem dates")
    func capturePredicate() throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(keywords: [], kind: .image, dateField: .captured))
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        let query = NSMetadataQuery()
        query.predicate = predicate
        #expect(predicate.predicateFormat.contains("kMDItemContentCreationDate"))
        #expect(predicate.predicateFormat.contains("kMDItemFSCreationDate") == false)
        #expect(query.predicate != nil)
    }

    @Test("Every file-kind predicate is accepted by the real Spotlight query parser", arguments: [
        SmartSearchInterpretation.Kind.any, .pdf, .document, .spreadsheet, .presentation,
        .image, .video, .audio, .folder, .archive, .code,
    ])
    func spotlightAcceptsKindPredicates(_ kind: SmartSearchInterpretation.Kind) throws {
        let plan = try SmartSearchTestFixtures.plan(SmartSearchTestFixtures.interpretation(kind: kind))
        let predicate = SmartSearchPredicateBuilder.predicate(for: plan)
        let query = NSMetadataQuery()
        query.predicate = predicate
        // This setter performs native predicate validation; malformed compound
        // trees previously crashed the app here with an Objective-C exception.
        query.searchScopes = [NSMetadataQueryIndexedLocalComputerScope]
        #expect(query.predicate != nil)
    }
}
