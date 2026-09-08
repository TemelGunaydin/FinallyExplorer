import Foundation

nonisolated enum OnDeviceModelError: LocalizedError, Equatable, Sendable {
    case unavailable(SmartRenameAvailability)
    case unsupportedLanguage
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable(.deviceNotEligible):
            "This feature requires a Mac that supports Apple Intelligence. Other file tools remain available."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings, then try again."
        case .unavailable:
            "The on-device model is not ready. Open AI Settings to check Apple Intelligence."
        case .unsupportedLanguage:
            "The on-device model does not support this language. Try English."
        case .timedOut:
            "The on-device response took too long. Try a shorter, more specific question."
        }
    }
}
