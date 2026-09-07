import Foundation
import UniformTypeIdentifiers

nonisolated enum SmartSearchPredicateBuilder {
    static func predicate(for plan: SmartSearchPlan) -> NSPredicate {
        var conditions = plan.keywords.map { term in
            let name = contains(term, key: NSMetadataItemFSNameKey)
            let content = contains(term, key: NSMetadataItemTextContentKey)
            return switch plan.area {
            case .names: name
            case .contents: content
            case .namesAndContents: combine([name, content], using: .or)
            }
        }
        if let typePredicate = kindPredicate(plan.kind) { conditions.append(typePredicate) }
        if plan.fileExtensions.isEmpty == false { conditions.append(extensions(plan.fileExtensions)) }
        if let interval = plan.dateInterval {
            let key = switch plan.dateField {
            case .created: "kMDItemFSCreationDate"
            case .modified: NSMetadataItemContentModificationDateKey
            // Spotlight supplies candidates; the service verifies the original
            // EXIF timestamp before presenting a captured-date match.
            case .captured: "kMDItemContentCreationDate"
            }
            conditions.append(NSPredicate(format: "%K >= %@", key, interval.start as NSDate))
            conditions.append(NSPredicate(format: "%K < %@", key, interval.end as NSDate))
        }
        return combine(conditions, using: .and)
    }

    private static func contains(_ text: String, key: String) -> NSPredicate {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
        // Values are substituted, never interpolated into predicate syntax.
        return NSPredicate(format: "%K LIKE[cd] %@", key, "*\(escaped)*")
    }

    private static func kindPredicate(_ kind: SmartSearchInterpretation.Kind) -> NSPredicate? {
        switch kind {
        case .any: return nil
        case .pdf: return contentType(UTType.pdf)
        case .image: return contentType(UTType.image)
        case .video: return contentType(UTType.movie)
        case .audio: return contentType(UTType.audio)
        case .folder: return contentType(UTType.folder)
        case .document:
            return extensions(["pdf", "doc", "docx", "pages", "odt", "rtf", "txt", "md"])
        case .spreadsheet:
            return extensions(["xls", "xlsx", "numbers", "ods", "csv", "tsv"])
        case .presentation:
            return extensions(["ppt", "pptx", "key", "odp"])
        case .archive:
            return extensions(["zip", "tar", "gz", "bz2", "xz", "7z", "rar"])
        case .code:
            return combine([
                contentType(UTType.sourceCode),
                extensions(["json", "yaml", "yml", "toml", "xml", "sql", "sh"]),
            ], using: .or)
        }
    }

    private static func contentType(_ type: UTType) -> NSPredicate {
        NSPredicate(format: "%K == %@", NSMetadataItemContentTypeTreeKey, type.identifier)
    }

    private static func extensions(_ values: [String]) -> NSPredicate {
        combine(values.map {
            NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*.\($0)")
        }, using: .or)
    }

    private static func combine(_ values: [NSPredicate], using type: NSCompoundPredicate.LogicalType) -> NSPredicate {
        // Spotlight throws Objective-C exceptions for unary compound predicates.
        guard values.count > 1 else { return values.first ?? NSPredicate(value: false) }
        return NSCompoundPredicate(type: type, subpredicates: values)
    }
}
