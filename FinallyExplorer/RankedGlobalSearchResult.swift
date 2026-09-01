//
//  RankedGlobalSearchResult.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct RankedGlobalSearchResult {
    let result: ExplorerSearchResult
    let quality: SearchTextMatch.Quality?
    let nativeScore: Int
}
