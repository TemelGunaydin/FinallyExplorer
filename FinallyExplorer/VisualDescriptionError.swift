import Foundation

nonisolated enum VisualDescriptionError: LocalizedError, Equatable, Sendable {
    case invalidRequest, unsupportedRequest, invalidInterpretation

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Describe a photo in English using up to 500 characters."
        case .unsupportedRequest:
            "Describe visible scenes or objects only. Dates, named places or people, exclusions and file operations are not supported in this photo view."
        case .invalidInterpretation:
            "The visual concepts could not be understood safely. Try a simpler description, or search observed labels directly."
        }
    }
}
