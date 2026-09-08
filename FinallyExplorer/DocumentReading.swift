import Foundation

nonisolated protocol DocumentReading: Sendable {
    func read(_ urls: [URL]) async throws -> [QuestionDocument]
    func validate(_ documents: [QuestionDocument]) async throws
}
