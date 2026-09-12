import Foundation

nonisolated enum DocumentQuestionError: LocalizedError, Equatable, Sendable {
    case selection, unsupported, tooLarge, unreadable, noText, changed, noEvidence, invalidAnswer, invalidQuestion, ambiguousFollowUp
    var errorDescription: String? {
        switch self {
        case .selection: "Select between 1 and 5 local PDF, TXT, MD, JSON, or CSV documents."
        case .unsupported: "Only local PDF, TXT, MD, JSON and CSV files are supported. Links and cloud placeholders are not read."
        case .tooLarge: "Choose smaller documents: 20 MB, 100 PDF pages and 200,000 text characters per file; 300,000 characters in total."
        case .unreadable: "This document cannot be read. Check its permissions, encoding, or PDF password."
        case .noText: "No readable text was found. Scanned/image-only PDFs need text recognition first."
        case .changed: "A selected document changed or disappeared. Read the documents again before asking another question."
        case .noEvidence: "I could not find supporting passages in the selected documents. Try a more specific question."
        case .invalidAnswer: "The answer could not be verified against the source excerpts. No unverified answer was shown."
        case .invalidQuestion: "Ask a specific question in English using up to 500 characters."
        case .ambiguousFollowUp: "Which document or subject do you mean? Name it in your question, or select New Conversation to start fresh."
        }
    }

    static func message(for error: any Error) -> String {
        // Descriptor helpers are shared with comparison tools; do not expose
        // their compare/copy-specific wording in this read-only feature.
        if error is FolderComparisonError || error is CocoaError { return unreadable.localizedDescription }
        return error.localizedDescription
    }
}
