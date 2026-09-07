import Foundation

/// Exact, allow-listed English shortcuts avoid inference latency and context drift.
/// Unrecognized or compound requests still go through the on-device model.
nonisolated enum SmartSearchQuickRefinement {
    static func resolve(_ query: String, previous: SmartSearchPlan, now: Date, calendar: Calendar) throws -> SmartSearchPlan? {
        let text = query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var search = SmartSearchInterpretation(
            area: previous.area, kind: previous.kind, location: previous.location,
            dateField: previous.dateField, dateRule: .none, dayCount: 0,
            startDate: "", endDate: "", keywords: [], unsupportedCriteria: []
        )
        var changed: [SmartSearchRefinement.Filter] = []
        let kinds: [String: SmartSearchInterpretation.Kind] = [
            "pdf": .pdf, "pdfs": .pdf, "images": .image, "photos": .image,
            "videos": .video, "audio": .audio, "folders": .folder,
            "documents": .document, "spreadsheets": .spreadsheet,
            "presentations": .presentation, "archives": .archive, "code files": .code,
        ]
        let extensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "gif", "webp", "tiff", "raw", "swift", "json", "md", "txt", "csv"]
        if text.hasPrefix("only ") {
            let value = String(text.dropFirst(5))
            if let kind = kinds[value] {
                search.kind = kind
                changed = [.kind, .fileExtensions]
            } else if extensions.contains(value) {
                search.fileExtensions = [value]
                changed = [.fileExtensions]
            }
        }
        for location in [SmartSearchInterpretation.Location.desktop, .downloads, .documents, .pictures, .music, .movies] {
            if text == "in \(location.rawValue) instead" || text == "only in \(location.rawValue)" {
                search.location = location
                changed = [.location]
            }
        }
        let dates: [String: SmartSearchInterpretation.DateRule] = [
            "last week instead": .lastWeek, "this week instead": .thisWeek,
            "last month instead": .lastMonth, "this month instead": .thisMonth,
        ]
        if let rule = dates[text] {
            search.dateRule = rule
            changed = [.date]
        } else if text == "yesterday instead" || text == "today instead" {
            search.dateRule = .daysAgo
            search.dayCount = text == "yesterday instead" ? 1 : 0
            changed = [.date]
        }
        guard changed.isEmpty == false else { return nil }
        return try SmartSearchRefinement(mode: .refine, changedFilters: changed, search: search)
            .resolve(previous: previous, now: now, calendar: calendar)
    }
}
