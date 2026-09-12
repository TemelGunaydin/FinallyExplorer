import Foundation

nonisolated protocol DocumentSemanticEncoding: Sendable {
    /// Nil means the local embedding is unavailable. Never requests a download.
    func vectors(for texts: [String]) async throws -> [[Double]]?
}
