import CoreGraphics

nonisolated protocol DocumentTextRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> String
}
