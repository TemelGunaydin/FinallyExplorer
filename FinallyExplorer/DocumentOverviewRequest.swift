import Foundation

/// Only whole-document requests bypass relevance ranking. Subject-specific
/// questions (including “explain the payment deadline”) still need evidence.
nonisolated enum DocumentOverviewRequest {
    static func matches(_ question: String) -> Bool {
        let words = question.lowercased().split { $0.isLetter == false && $0.isNumber == false }
            .filter { $0 != "please" }.joined(separator: " ")
        return words.range(
            of:
                #"^(?:(?:can|could|would) you )?(?:(?:explain|summarize|summarise|describe) (?:(?:the|this|these|selected|my) )?(?:documents?|files?|text)(?: in (?:simple|plain) english)?|(?:give me )?(?:a |an )?(?:summary|overview)(?: of (?:(?:the|this|these|selected|my) )?(?:documents?|files?|text))?|what (?:is this document|are these documents) about)$"#,
            options: .regularExpression) != nil
    }

    static func excerpts(from index: DocumentRetrievalIndex) throws -> [DocumentPassage] {
        var order: [UUID] = []
        var groups: [UUID: [DocumentPassage]] = [:]
        for excerpt in index.excerpts {
            try Task.checkCancellation()
            if groups[excerpt.documentID] == nil { order.append(excerpt.documentID) }
            groups[excerpt.documentID, default: []].append(excerpt)
        }
        guard order.isEmpty == false else { return [] }
        // Cover every selected document, sharing the existing 2,400-byte budget.
        // A long document gets representative beginning/middle/end windows;
        // this is explicitly an excerpt overview, never a full-document summary.
        let capacity = max(4, order.count)
        let byteLimit = 2_400 / capacity
        var selected: [DocumentPassage] = []
        for (position, id) in order.enumerated() {
            try Task.checkCancellation()
            guard let windows = groups[id] else { continue }
            let quota = min(windows.count, capacity / order.count + (position < capacity % order.count ? 1 : 0))
            for slot in 0..<quota {
                let offset = quota == 1 ? 0 : slot * (windows.count - 1) / (quota - 1)
                let window = windows[offset]
                // Windows from one original passage need distinct request-local
                // IDs so quote validation cannot bind to a different window.
                selected.append(
                    DocumentPassage(
                        id: -(selected.count + 1), documentID: id,
                        fileName: window.fileName, page: window.page,
                        text: LocalDocumentPassageSearch.bytePrefix(window.text[...], limit: byteLimit),
                        isOCR: window.isOCR))
            }
        }
        return selected
    }
}
