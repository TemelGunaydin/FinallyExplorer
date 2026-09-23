import Darwin
import Foundation

nonisolated enum DocumentQuestionError: LocalizedError, Equatable, Sendable {
    case selection, unsupported, unreadable, noText, changed, noEvidence, invalidAnswer, invalidQuestion, ambiguousFollowUp
    case accessDenied, missing, notDownloaded, linkedFile, passwordProtected, invalidPDF, unsupportedTextEncoding
    case fileSizeLimit, pdfPageLimit(Int), textLimit, totalTextLimit
    case ocrLimit, ocrFailed, ocrTimedOut
    var errorDescription: String? {
        switch self {
        case .selection: "Select between 1 and 5 local PDF, TXT, MD, JSON, or CSV documents."
        case .unsupported: "Only local PDF, TXT, MD, JSON and CSV files are supported. Links and cloud placeholders are not read."
        case .fileSizeLimit: "This file exceeds the 20 MB limit. Choose a smaller file."
        case let .pdfPageLimit(count): "This PDF has \(count) pages; the limit is 100. Choose a shorter PDF or export just the pages you need."
        case .textLimit: "This document exceeds the 200,000-character limit. Choose a shorter document or an excerpt."
        case .totalTextLimit: "These documents exceed the combined 300,000-character limit. Select fewer or shorter documents."
        case .accessDenied: "Access was denied. Select the file again using Choose Documents. If it still fails, check its permissions in Finder."
        case .missing: "This file is no longer available. Select it again using Choose Documents."
        case .notDownloaded: "This file is not downloaded. Download it in Finder, then try again."
        case .linkedFile: "Links are not supported. Select the original document instead."
        case .passwordProtected: "This PDF requires a password. Open it in Preview and export an unencrypted copy, then select that copy."
        case .invalidPDF: "This PDF could not be opened. Check it in Preview, then try a newly exported or downloaded copy."
        case .unsupportedTextEncoding: "This file is not readable as UTF-8 text. Save a UTF-8 copy in a text editor, then select it."
        case .unreadable: "This file could not be read. Try selecting it again or use another copy."
        case .noText: "No readable text was found. For scans, try a clearer PDF with printed English text."
        case .changed: "A selected document changed or disappeared. Read the documents again before asking another question."
        case .noEvidence: "No supported answer was found. Try asking about a specific detail in the document."
        case .invalidAnswer: "The answer could not be verified against the source excerpts. No unverified answer was shown."
        case .invalidQuestion: "Ask a specific question in English using up to 500 characters."
        case .ambiguousFollowUp: "Which document or subject do you mean? Name it in your question, or select New Conversation to start fresh."
        case .ocrLimit: "Choose a smaller scan: up to 20 PDF pages needing OCR per read, and 20,000 recognized characters per page."
        case .ocrFailed: "Text recognition could not finish. Try a clearer or smaller PDF. No partial document context was added."
        case .ocrTimedOut: "Text recognition took too long on one page. Try a smaller or clearer scan."
        }
    }

    static func message(for error: any Error) -> String {
        // Descriptor helpers are shared with comparison tools; do not expose
        // their compare/copy-specific wording in this read-only feature.
        if error is FolderComparisonError || error is CocoaError || error is POSIXError {
            return readReason(for: error).localizedDescription
        }
        return error.localizedDescription
    }

    static func readReason(for error: any Error) -> Self {
        if let failure = error as? DocumentReadFailure { return failure.reason }
        if let reason = error as? Self { return reason }
        if let error = error as? FolderComparisonError {
            switch error {
            case let .fileSystem(_, code): return fileSystemReason(code)
            case .changed: return .changed
            default: return .unreadable
            }
        }
        if let error = error as? POSIXError { return fileSystemReason(error.code.rawValue) }
        if let error = error as? CocoaError {
            switch error.code {
            case .fileReadNoPermission: return .accessDenied
            case .fileReadNoSuchFile, .fileNoSuchFile: return .missing
            default: return .unreadable
            }
        }
        return .unreadable
    }

    private static func fileSystemReason(_ code: Int32) -> Self {
        switch code {
        case EACCES, EPERM: .accessDenied
        case ENOENT, ENOTDIR: .missing
        case ELOOP: .linkedFile
        default: .unreadable
        }
    }
}
