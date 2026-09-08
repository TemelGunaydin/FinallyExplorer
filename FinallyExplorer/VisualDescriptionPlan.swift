import Foundation

nonisolated struct VisualDescriptionPlan: Equatable, Sendable {
    /// Every concept is required; alternatives within one concept are OR matches.
    let concepts: [[String]]

    init(concepts: [[String]]) throws {
        guard (1...4).contains(concepts.count), concepts.allSatisfy({ alternatives in
            (1...8).contains(alternatives.count) && alternatives.allSatisfy {
                $0.isEmpty == false && $0.count <= 40 && $0.unicodeScalars.allSatisfy { CharacterSet.letters.union(.whitespaces).contains($0) }
            }
        }) else { throw VisualDescriptionError.invalidInterpretation }
        self.concepts = concepts.map { $0.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
        guard self.concepts.allSatisfy({ $0.allSatisfy { $0.isEmpty == false } }) else { throw VisualDescriptionError.invalidInterpretation }
    }

    var explanation: String { concepts.map { $0.joined(separator: " / ") }.joined(separator: " + ") }

    func matchingLabels(in evidence: VisualImageEvidence) -> [String]? {
        let matching = concepts.map { alternatives in
            evidence.labels.map(\.name).filter { label in
                alternatives.contains { term in
                    label.range(of: "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
                }
            }
        }
        guard matching.allSatisfy({ $0.isEmpty == false }) else { return nil }
        return Array(Set(matching.flatMap { $0 })).sorted()
    }

    @concurrent func search(_ entries: [VisualSearchSnapshot.Entry]) async throws -> [VisualSearchMatch] {
        var results: [VisualSearchMatch] = []
        for entry in entries {
            try Task.checkCancellation()
            if let labels = matchingLabels(in: entry.evidence) {
                results.append(VisualSearchMatch(entry: entry, labels: labels, excerpt: nil))
            }
        }
        return results
    }
}
