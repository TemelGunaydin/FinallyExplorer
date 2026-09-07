import Foundation

nonisolated struct AskAISearchTurn: Identifiable, Sendable {
    let id = UUID()
    let request: String
    let response: String
    let isError: Bool
}
