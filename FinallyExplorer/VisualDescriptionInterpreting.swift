import Foundation

nonisolated protocol VisualDescriptionInterpreting: Sendable {
    func interpret(_ query: String) async throws -> VisualDescriptionPlan
}
