import Foundation

nonisolated struct DocumentPageText: Sendable {
    let number: Int?
    var text: String
    var isOCR = false
}
