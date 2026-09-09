import Foundation

nonisolated enum VisualDescriptionError: LocalizedError, Equatable, Sendable {
    case invalidRequest, unsupportedRequest, invalidInterpretation, missingContext

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Describe a photo in English using up to 500 characters."
        case .unsupportedRequest:
            "Use visible scenes, a capture date (for example ‘from last week’), or a supported image type. Follow up with ‘Only HEIC’, ‘Yesterday instead’, ‘All dates’, or ‘All image types’. Named places or people, exclusions and file operations are not supported."
        case .invalidInterpretation:
            "The visual concepts could not be understood safely. Try a simpler description, or search observed labels directly."
        case .missingContext:
            "First describe the photos, for example ‘Find beach photos from last week’. Then refine the results with a date or image type."
        }
    }
}
