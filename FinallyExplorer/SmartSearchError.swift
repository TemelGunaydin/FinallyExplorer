import Foundation

nonisolated enum SmartSearchError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case unsupportedRequest
    case invalidInterpretation
    case unavailable(SmartRenameAvailability)
    case unsupportedLanguage
    case timedOut
    case interpretationFailed
    case locationOutsideRoot

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Describe the file in a short sentence (up to 500 characters)."
        case .unsupportedRequest:
            "Try a topic, file type, date, or a standard folder such as Downloads. This request includes something Smart Search cannot filter yet."
        case .invalidInterpretation:
            "The search filters could not be understood safely. Try a more specific description, or use normal search."
        case .unavailable(.deviceNotEligible):
            "Smart Search requires a Mac that supports Apple Intelligence. Normal search is still available."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings to use Smart Search. Normal search is still available."
        case .unavailable:
            "The on-device model is not ready. Check Apple Intelligence in Settings, or use normal search."
        case .unsupportedLanguage:
            "The on-device model does not support this language. Try English, or use normal search."
        case .timedOut:
            "Smart Search took too long. Try a shorter description, or use normal search."
        case .interpretationFailed:
            "The on-device model could not interpret this search. Try rephrasing it, or use normal search."
        case .locationOutsideRoot:
            "That location is outside the current search area. Try searching without a location."
        }
    }
}
