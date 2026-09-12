import CoreGraphics
import Foundation
import Vision

nonisolated struct VisionDocumentTextRecognizer: DocumentTextRecognizing {
    @concurrent func recognize(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        guard image.width <= 2_400, image.height <= 2_400 else { throw DocumentQuestionError.ocrLimit }
        do {
            return try await Self.bounded {
                var request = RecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
                request.automaticallyDetectsLanguage = false
                request.usesLanguageCorrection = false
                let observations = try await request.perform(on: image, orientation: .up)
                try Task.checkCancellation()
                var text = ""
                for observation in observations {
                    try Task.checkCancellation()
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    guard text.count + candidate.string.count + 1 <= 20_000 else { throw DocumentQuestionError.ocrLimit }
                    text += candidate.string + "\n"
                }
                return text
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as DocumentQuestionError { throw error }
        catch { throw DocumentQuestionError.ocrFailed }
    }

    static func bounded(timeout: Duration = .seconds(15), work: @escaping @Sendable () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DocumentQuestionError.ocrTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        }
    }
}
