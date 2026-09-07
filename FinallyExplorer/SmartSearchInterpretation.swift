import FoundationModels

/// A constrained interpretation, never executable code, a predicate, or a path.
@Generable
nonisolated struct SmartSearchInterpretation: Equatable, Sendable {
    var area: Area

    @Guide(description: "Only an explicitly named file format. A topic such as 'accounting report' has kind any, because a report could be any format. PDFs have kind pdf.")
    var kind: Kind
    var location: Location
    var dateField: DateField
    var dateRule: DateRule

    @Guide(description: "Number of calendar days for daysAgo or lastDays. Today = 0, yesterday = 1. Otherwise 0.", .range(0...3650))
    var dayCount: Int

    @Guide(description: "YYYY-MM-DD only for onDate or dateRange; otherwise an empty string.")
    var startDate: String

    @Guide(description: "Inclusive YYYY-MM-DD end date only for dateRange; otherwise an empty string.")
    var endDate: String

    @Guide(description: "Preserve ALL topic/subject nouns, including report, notes, invoice. Remove only commands and the extracted type/location/date words. 'Find financial report from yesterday' -> [financial, report]. 'PDFs in Downloads from last week' -> []. Keep the user's language.", .maximumCount(6))
    var keywords: [String]

    @Guide(description: "Only specific extensions such as heic, jpg, swift, json. Lowercase, no dot. For PDFs use kind pdf and EMPTY fileExtensions. For photos/images use kind image and EMPTY fileExtensions. Empty unless a particular extension is requested. Never put extensions in keywords.", .maximumCount(6))
    var fileExtensions: [String] = []

    @Guide(description: "Only extra requests that the fields above cannot represent: e.g. delete, move, size over 2 GB, or excluding a type. Empty array when all criteria are represented. A type/date-only search with no keywords IS valid; use an empty array.", .maximumCount(3))
    var unsupportedCriteria: [String]

    var isSupported: Bool { unsupportedCriteria.isEmpty }

    @Generable
    enum Area: String, Equatable, Sendable {
        case names, contents, namesAndContents
    }

    @Generable
    enum Kind: String, Equatable, Sendable {
        case any, pdf, document, spreadsheet, presentation, image, video, audio, folder, archive, code
    }

    @Generable
    enum Location: String, Equatable, Sendable {
        case anywhere, desktop, downloads, documents, pictures, music, movies
    }

    @Generable
    enum DateField: String, Equatable, Sendable {
        case modified, created, captured
    }

    @Generable
    enum DateRule: String, Equatable, Sendable {
        case none, daysAgo, lastDays, thisWeek, lastWeek, thisMonth, lastMonth, onDate, dateRange
    }
}
