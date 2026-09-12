import Foundation

nonisolated struct DocumentPassage: Identifiable, Sendable {
    let id: Int
    let documentID: UUID
    let fileName: String
    let page: Int?
    let text: String
    var isOCR = false
    var sourceLabel: String { fileName + (page.map { " · page \($0)" } ?? " · text excerpt") + (isOCR ? " · OCR" : "") }
}
