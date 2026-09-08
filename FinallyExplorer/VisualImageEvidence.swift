import Foundation

nonisolated struct VisualImageEvidence: Sendable {
    struct Label: Equatable, Sendable {
        let name: String
        let confidence: Float
    }

    let labels: [Label]
    let text: String
    let textWasTruncated: Bool
    let thumbnail: Data
}

nonisolated protocol VisualImageAnalyzing: Sendable {
    func analyze(_ data: Data) async throws -> VisualImageEvidence
}
