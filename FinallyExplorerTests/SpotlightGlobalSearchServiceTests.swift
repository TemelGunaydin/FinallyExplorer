//
//  SpotlightGlobalSearchServiceTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct SpotlightGlobalSearchServiceTests {
    @Test("A single-token query uses a Spotlight leaf predicate")
    func singleTokenQueryDoesNotCreateUnaryOrPredicate() {
        let predicate = SpotlightNamePredicateBuilder.predicate(for: "api")

        #expect(predicate is NSCompoundPredicate == false)

        // Assigning the scope makes NSMetadataQuery validate its predicate.
        // Before this regression fix, the unary OR predicate raised an
        // uncaught NSInvalidArgumentException at this exact point.
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = [NSMetadataQueryIndexedLocalComputerScope]
    }

    @Test("A multi-token query keeps its alternative Spotlight predicates")
    func multiTokenQueryUsesCompoundAlternatives() throws {
        let predicate = SpotlightNamePredicateBuilder.predicate(
            for: "api design"
        )
        let compound = try #require(predicate as? NSCompoundPredicate)

        #expect(compound.compoundPredicateType == .or)
        #expect(compound.subpredicates.count > 1)
    }
}
