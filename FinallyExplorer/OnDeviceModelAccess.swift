import Foundation
import FoundationModels
import NaturalLanguage

nonisolated enum OnDeviceModelAccess {
    static func check(_ model: SystemLanguageModel, query: String) throws {
        try checkAvailability(model)
        if let language = NLLanguageRecognizer.dominantLanguage(for: query),
           model.supportsLocale(Locale(identifier: language.rawValue)) == false { throw OnDeviceModelError.unsupportedLanguage }
    }

    static func checkAvailability(_ model: SystemLanguageModel) throws {
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): throw OnDeviceModelError.unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): throw OnDeviceModelError.unavailable(.appleIntelligenceNotEnabled)
        case .unavailable: throw OnDeviceModelError.unavailable(.modelNotReady)
        }
    }

    static func bounded<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(for: .seconds(30)); throw OnDeviceModelError.timedOut }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        }
    }
}
