import Foundation

/// Exact English filters only. Unknown words stay in the scene request, where
/// the interpreter must reject unsupported criteria rather than broaden a search.
nonisolated enum VisualPhotoRequest {
    struct Initial: Sendable {
        let scene: String
        let filters: VisualPhotoFilters
    }

    static func initial(_ query: String, now: Date, calendar: Calendar) throws -> Initial {
        var scene = normalized(query)
        var interval: DateInterval?
        var extensions: [String] = []
        if let match = captures(#" (?:from |taken |shot |captured )?(yesterday|today|last week|this week|last month|this month|(?:the )?last \d{1,4} days|\d{1,4} days? ago|on \d{4}-\d{2}-\d{2}|between \d{4}-\d{2}-\d{2} and \d{4}-\d{2}-\d{2})$"#, in: scene) {
            interval = try dateInterval(match[1], now: now, calendar: calendar)
            scene = String(scene.dropLast(match[0].count))
        }
        // A format before “photos” or at the end is unambiguous, unlike a scene
        // label or OCR text that happens to mention a file extension.
        if let match = captures(#"\b(heic|heif|jpg|jpeg|png|tif|tiff|bmp) (?=(?:(?:beach|seaside|coastal) )?(?:photos?|pictures?|images?)\b)"#, in: scene),
           let range = scene.range(of: match[0]) {
            extensions = [match[1]]
            scene.removeSubrange(range)
        } else if let match = captures(#" in (heic|heif|jpg|jpeg|png|tif|tiff|bmp)(?: format)?$"#, in: scene) {
            extensions = [match[1]]
            scene = String(scene.dropLast(match[0].count))
        }
        return try Initial(scene: scene, filters: VisualPhotoFilters(captureInterval: interval, fileExtensions: extensions))
    }

    static func isFollowUp(_ query: String) -> Bool {
        let text = normalized(query)
        return text.hasPrefix("only ") || text.hasSuffix(" instead") || text.hasPrefix("from ")
            || text == "all dates" || text == "all image types"
    }

    static func refine(_ query: String, previous: VisualDescriptionPlan, now: Date, calendar: Calendar) throws -> VisualDescriptionPlan? {
        let text = normalized(query)
        var interval = previous.filters.captureInterval
        var extensions = previous.filters.fileExtensions
        if text == "all image types" { extensions = [] }
        else if text == "all dates" { interval = nil }
        else if let match = captures(#"^only (heic|heif|jpg|jpeg|png|tif|tiff|bmp)(?: photos?| pictures?| images?)?$"#, in: text) {
            extensions = [match[1]]
        } else if text.hasSuffix(" instead") || text.hasPrefix("from ") {
            var date = text
            if date.hasSuffix(" instead") { date = String(date.dropLast(8)) }
            if date.hasPrefix("from ") { date = String(date.dropFirst(5)) }
            interval = try dateInterval(date, now: now, calendar: calendar)
        } else if isFollowUp(text) {
            throw VisualDescriptionError.unsupportedRequest
        } else { return nil }
        return try VisualDescriptionPlan(concepts: previous.concepts,
            filters: VisualPhotoFilters(captureInterval: interval, fileExtensions: extensions))
    }

    static func dateInterval(_ text: String, now: Date, calendar: Calendar) throws -> DateInterval {
        var value = SmartSearchInterpretation(area: .names, kind: .image, location: .anywhere, dateField: .captured,
            dateRule: .none, dayCount: 0, startDate: "", endDate: "", keywords: [], unsupportedCriteria: [])
        let rules: [String: SmartSearchInterpretation.DateRule] = [
            "this week": .thisWeek, "last week": .lastWeek, "this month": .thisMonth, "last month": .lastMonth,
        ]
        if text == "yesterday" || text == "today" {
            value.dateRule = .daysAgo; value.dayCount = text == "yesterday" ? 1 : 0
        } else if let rule = rules[text] { value.dateRule = rule }
        else if let match = captures(#"^(\d{1,4}) days? ago$"#, in: text), let count = Int(match[1]) {
            value.dateRule = .daysAgo; value.dayCount = count
        } else if let match = captures(#"^(?:the )?last (\d{1,4}) days$"#, in: text), let count = Int(match[1]) {
            value.dateRule = .lastDays; value.dayCount = count
        } else if let match = captures(#"^on (\d{4}-\d{2}-\d{2})$"#, in: text) {
            value.dateRule = .onDate; value.startDate = match[1]
        } else if let match = captures(#"^between (\d{4}-\d{2}-\d{2}) and (\d{4}-\d{2}-\d{2})$"#, in: text) {
            value.dateRule = .dateRange; value.startDate = match[1]; value.endDate = match[2]
        } else { throw VisualDescriptionError.unsupportedRequest }
        guard let interval = try SmartSearchPlan(interpretation: value, now: now, calendar: calendar).dateInterval else {
            throw VisualDescriptionError.invalidInterpretation
        }
        return interval
    }

    private static func normalized(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
