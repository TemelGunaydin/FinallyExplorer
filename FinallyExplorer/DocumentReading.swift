import Foundation

nonisolated protocol DocumentReading: Sendable {
    func read(_ urls: [URL]) async throws -> [QuestionDocument]
    func read(_ urls: [URL], progress: @escaping @Sendable (DocumentReadProgress) async -> Void) async throws -> [QuestionDocument]
    func validate(_ documents: [QuestionDocument]) async throws
}

extension DocumentReading {
    func read(_ urls: [URL], progress: @escaping @Sendable (DocumentReadProgress) async -> Void) async throws -> [QuestionDocument] {
        try await read(urls)
    }
}
