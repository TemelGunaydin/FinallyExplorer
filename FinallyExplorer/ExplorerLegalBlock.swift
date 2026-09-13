import Foundation

/// The bundled documents use only headings, paragraphs, and inline Markdown links.
nonisolated struct ExplorerLegalBlock: Identifiable, Sendable {
    let id: Int
    let text: String
    let isHeading: Bool

    static func parse(_ document: String) -> [Self] {
        document.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .enumerated()
            .map { index, paragraph in
                let isHeading = paragraph.hasPrefix("## ")
                return Self(id: index, text: isHeading ? String(paragraph.dropFirst(3)) : paragraph,
                            isHeading: isHeading)
            }
    }
}
