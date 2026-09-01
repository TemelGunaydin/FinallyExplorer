//
//  SearchTextMatch.swift
//  FinallyExplorer
//

import Foundation

/// Finds the tightest ordered character match used by fuzzy-search rows.
/// A contiguous match wins; otherwise the smallest subsequence window wins.
nonisolated enum SearchTextMatch {
    struct Match {
        let ranges: [Range<String.Index>]
        let quality: Quality
    }

    struct Quality: Comparable {
        let tier: Int
        let span: Int
        let startOffset: Int
        let candidateLength: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.span != rhs.span { return lhs.span < rhs.span }
            if lhs.startOffset != rhs.startOffset {
                return lhs.startOffset < rhs.startOffset
            }
            return lhs.candidateLength < rhs.candidateLength
        }
    }

    static func ranges(
        in text: String,
        matching rawQuery: String
    ) -> [Range<String.Index>] {
        match(in: text, matching: rawQuery)?.ranges ?? []
    }

    static func match(
        in text: String,
        matching rawQuery: String
    ) -> Match? {
        let trimmedQuery = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard text.isEmpty == false, trimmedQuery.isEmpty == false else {
            return nil
        }

        let bestMatch = match(in: text, literalQuery: trimmedQuery)
        let compactQuery = trimmedQuery.filter { $0.isWhitespace == false }

        if compactQuery != trimmedQuery,
           let compactMatch = match(in: text, literalQuery: compactQuery) {
            if let bestMatch {
                if compactMatch.quality < bestMatch.quality {
                    return compactMatch
                }
            } else {
                return compactMatch
            }
        }

        return bestMatch
    }

    private static func match(
        in text: String,
        literalQuery query: String
    ) -> Match? {
        guard query.isEmpty == false else { return nil }

        if let contiguousRange = text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            let startOffset = text.distance(
                from: text.startIndex,
                to: contiguousRange.lowerBound
            )
            let isExact = text.compare(
                query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame

            return Match(
                ranges: [contiguousRange],
                quality: Quality(
                    tier: isExact ? 0 : (startOffset == 0 ? 1 : 2),
                    span: text.distance(
                        from: contiguousRange.lowerBound,
                        to: contiguousRange.upperBound
                    ),
                    startOffset: startOffset,
                    candidateLength: text.count
                )
            )
        }

        let candidateRanges = characterRanges(in: text)
        let queryCharacters = Array(query)
        guard queryCharacters.count <= candidateRanges.count else { return nil }

        var bestRanges: [Range<String.Index>] = []
        var bestSpan = Int.max
        var bestStartOffset = Int.max

        for startOffset in candidateRanges.indices {
            guard charactersMatch(
                text[candidateRanges[startOffset]],
                queryCharacters[0]
            ) else {
                continue
            }

            var matchedRanges = [candidateRanges[startOffset]]
            var queryOffset = 1
            var candidateOffset = startOffset + 1

            while queryOffset < queryCharacters.count,
                  candidateOffset < candidateRanges.count {
                let candidateRange = candidateRanges[candidateOffset]
                if charactersMatch(
                    text[candidateRange],
                    queryCharacters[queryOffset]
                ) {
                    matchedRanges.append(candidateRange)
                    queryOffset += 1
                }
                candidateOffset += 1
            }

            guard queryOffset == queryCharacters.count else {
                continue
            }

            let endOffset = candidateOffset - 1
            let span = endOffset - startOffset + 1
            if span < bestSpan || (span == bestSpan && startOffset < bestStartOffset) {
                bestSpan = span
                bestStartOffset = startOffset
                bestRanges = matchedRanges
            }
        }

        guard bestRanges.isEmpty == false else { return nil }
        return Match(
            ranges: bestRanges,
            quality: Quality(
                tier: 3,
                span: bestSpan,
                startOffset: bestStartOffset,
                candidateLength: candidateRanges.count
            )
        )
    }

    private static func characterRanges(
        in text: String
    ) -> [Range<String.Index>] {
        var output: [Range<String.Index>] = []
        output.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            output.append(index..<nextIndex)
            index = nextIndex
        }
        return output
    }

    private static func charactersMatch(
        _ candidate: Substring,
        _ query: Character
    ) -> Bool {
        String(candidate).compare(
            String(query),
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
}
