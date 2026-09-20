import Foundation

/// Keeps the actionable reason and the affected filename, never a private full path.
nonisolated struct DocumentReadFailure: LocalizedError, Equatable, Sendable {
    let fileName: String
    let reason: DocumentQuestionError

    var errorDescription: String? { "\(fileName)\n\(reason.localizedDescription)" }
}
