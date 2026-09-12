import Foundation

nonisolated struct DocumentReadProgress: Sendable {
    let fileName: String
    let page: Int
    let pageCount: Int

    var message: String { "Recognizing text in \(fileName) · page \(page) of \(pageCount)…" }
}
