import Foundation

/// Validated, read-only filters. Relative dates are resolved by Calendar, not LLM arithmetic.
nonisolated struct SmartSearchPlan: Equatable, Sendable {
    let keywords: [String]
    let area: SmartSearchInterpretation.Area
    let kind: SmartSearchInterpretation.Kind
    let location: SmartSearchInterpretation.Location
    let dateField: SmartSearchInterpretation.DateField
    let dateInterval: DateInterval?
    let fileExtensions: [String]

    init(
        interpretation: SmartSearchInterpretation,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        guard interpretation.isSupported else { throw SmartSearchError.unsupportedRequest }
        try self.init(
            keywords: interpretation.keywords, area: interpretation.area,
            kind: interpretation.kind, location: interpretation.location,
            dateField: interpretation.dateField,
            dateInterval: Self.resolveDate(interpretation, now: now, calendar: calendar),
            fileExtensions: interpretation.fileExtensions
        )
    }

    init(refining previous: Self, with update: SmartSearchRefinement, now: Date, calendar: Calendar) throws {
        guard update.search.isSupported else { throw SmartSearchError.unsupportedRequest }
        let changed = Set(update.changedFilters)
        let value = update.search
        try self.init(
            keywords: changed.contains(.keywords) ? value.keywords : previous.keywords,
            area: changed.contains(.area) ? value.area : previous.area,
            kind: changed.contains(.kind) ? value.kind : previous.kind,
            location: changed.contains(.location) ? value.location : previous.location,
            dateField: changed.contains(.date) ? value.dateField : previous.dateField,
            dateInterval: changed.contains(.date)
                ? Self.resolveDate(value, now: now, calendar: calendar) : previous.dateInterval,
            fileExtensions: changed.contains(.fileExtensions) ? value.fileExtensions : previous.fileExtensions
        )
    }

    private init(
        keywords: [String], area: SmartSearchInterpretation.Area,
        kind: SmartSearchInterpretation.Kind, location: SmartSearchInterpretation.Location,
        dateField: SmartSearchInterpretation.DateField, dateInterval: DateInterval?,
        fileExtensions: [String]
    ) throws {
        let terms = keywords.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard terms.count <= 6, terms.allSatisfy({ term in
            term.isEmpty == false && term.count <= 80
                && term.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) == false
                && term.contains("/") == false && term.contains("\\") == false
        }) else { throw SmartSearchError.invalidInterpretation }

        var seen = Set<String>()
        self.keywords = terms.filter { seen.insert($0.lowercased()).inserted }
        let extensions = fileExtensions.map { $0.lowercased() }
        guard extensions.count <= 6, extensions.allSatisfy({ value in
            value.isEmpty == false && value.count <= 12 && value.utf8.allSatisfy {
                (97...122).contains($0) || (48...57).contains($0)
            }
        }) else { throw SmartSearchError.invalidInterpretation }
        self.fileExtensions = Array(Set(extensions)).sorted()
        self.area = area
        self.kind = dateField == .captured && kind == .any ? .image : kind
        self.location = location
        self.dateField = dateField
        self.dateInterval = dateInterval
        guard dateField != .captured || self.kind == .image else {
            throw SmartSearchError.unsupportedRequest
        }
        guard self.keywords.isEmpty == false || self.kind != .any || dateInterval != nil
                || self.fileExtensions.isEmpty == false else {
            throw SmartSearchError.invalidInterpretation
        }
    }

    var highlightQuery: String { keywords.joined(separator: " ") }

    func filterLabels(locale: Locale = .current, timeZone: TimeZone = .current) -> [String] {
        let areaLabel = switch area {
        case .names: "Names"
        case .contents: "Indexed contents"
        case .namesAndContents: "Names & indexed contents"
        }
        var labels = [areaLabel]
        if keywords.isEmpty == false { labels.append(keywords.joined(separator: " + ")) }
        if kind != .any { labels.append(kind == .pdf ? "PDF" : kind.rawValue.capitalized) }
        if fileExtensions.isEmpty == false { labels.append(fileExtensions.map { ".\($0)" }.joined(separator: ", ")) }
        if location != .anywhere { labels.append(location.rawValue.capitalized) }
        if let dateInterval {
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
            let start = dateInterval.start.formatted(style)
            let end = dateInterval.end.addingTimeInterval(-1).formatted(style)
            let dateLabel = switch dateField {
            case .created: "Created"
            case .modified: "Modified"
            case .captured: "Captured (EXIF)"
            }
            labels.append("\(dateLabel): \(start == end ? start : "\(start) – \(end)")")
        }
        return labels
    }

    /// Only bounded filter values, never file contents or result names, enter the model context.
    func conversationContext() throws -> String {
        let fields = [
            "keywords": keywords.joined(separator: " + "), "area": area.rawValue,
            "kind": kind.rawValue, "location": location.rawValue,
            "fileExtensions": fileExtensions.joined(separator: ", "), "dateField": dateField.rawValue,
            "dateStart": dateInterval?.start.ISO8601Format() ?? "none",
            "dateEndExclusive": dateInterval?.end.ISO8601Format() ?? "none",
        ]
        return String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
    }

    func searchRoot(in rootURL: URL, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard FFFSearchValueMapper.isLocalFileURL(root) else {
            throw SmartSearchError.locationOutsideRoot
        }
        guard location != .anywhere else { return root }
        let candidate = homeURL.appending(path: location.rawValue.capitalized, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        let path = Self.normalizedPath(root)
        guard path == "/" || candidate == root
                || Self.normalizedPath(candidate).hasPrefix(path + "/") else {
            throw SmartSearchError.locationOutsideRoot
        }
        return candidate
    }

    static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path != "/" && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func resolveDate(
        _ value: SmartSearchInterpretation,
        now: Date,
        calendar: Calendar
    ) throws -> DateInterval? {
        guard (0...3650).contains(value.dayCount) else { throw SmartSearchError.invalidInterpretation }
        let today = calendar.startOfDay(for: now)
        switch value.dateRule {
        case .none:
            return nil
        case .daysAgo:
            guard let day = calendar.date(byAdding: .day, value: -value.dayCount, to: today),
                  let interval = calendar.dateInterval(of: .day, for: day) else {
                throw SmartSearchError.invalidInterpretation
            }
            return interval
        case .lastDays:
            guard value.dayCount > 0,
                  let start = calendar.date(byAdding: .day, value: 1 - value.dayCount, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: today) else {
                throw SmartSearchError.invalidInterpretation
            }
            return DateInterval(start: start, end: end)
        case .thisWeek, .lastWeek, .thisMonth, .lastMonth:
            let component: Calendar.Component = value.dateRule == .thisWeek || value.dateRule == .lastWeek
                ? .weekOfYear : .month
            let offset = value.dateRule == .lastWeek || value.dateRule == .lastMonth ? -1 : 0
            guard let day = calendar.date(byAdding: component, value: offset, to: today),
                  let interval = calendar.dateInterval(of: component, for: day) else {
                throw SmartSearchError.invalidInterpretation
            }
            return interval
        case .onDate, .dateRange:
            let start = try isoDay(value.startDate, timeZone: calendar.timeZone)
            let lastDay = value.dateRule == .onDate
                ? start : try isoDay(value.endDate, timeZone: calendar.timeZone)
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            guard lastDay >= start,
                  let end = gregorian.date(byAdding: .day, value: 1, to: lastDay) else {
                throw SmartSearchError.invalidInterpretation
            }
            return DateInterval(start: start, end: end)
        }
    }

    private static func isoDay(_ value: String, timeZone: TimeZone) throws -> Date {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1900...2200).contains(year) else { throw SmartSearchError.invalidInterpretation }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else {
            throw SmartSearchError.invalidInterpretation
        }
        return date
    }
}
