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
    var captureDate: PhotoCaptureDate? = nil
}

nonisolated protocol VisualImageAnalyzing: Sendable {
    func analyze(_ data: Data) async throws -> VisualImageEvidence
}
