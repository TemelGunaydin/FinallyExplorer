import Darwin
import Foundation

nonisolated struct LocalDocumentReader: DocumentReading {
    static let extensions: Set<String> = ["pdf", "txt", "md", "json", "csv"]
    var textRecognizer: any DocumentTextRecognizing = VisionDocumentTextRecognizer()
    var maximumOCRPages = 20

    @concurrent func read(_ urls: [URL]) async throws -> [QuestionDocument] {
        try await read(urls, progress: { _ in })
    }

    @concurrent func read(_ urls: [URL], progress: @escaping @Sendable (DocumentReadProgress) async -> Void) async throws -> [QuestionDocument] {
        guard (1...5).contains(urls.count), Set(urls).count == urls.count else { throw DocumentQuestionError.selection }
        var documents: [QuestionDocument] = []
        var nextID = 1, totalCharacters = 0, remainingOCRPages = max(0, min(20, maximumOCRPages))
        for selected in urls {
            try Task.checkCancellation()
            guard selected.isFileURL, selected.host == nil || selected.host == "" || selected.host == "localhost",
                  Self.extensions.contains(selected.pathExtension.lowercased()) else { throw DocumentQuestionError.unsupported }
            let parentURL = selected.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            guard try parentURL.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else { throw DocumentQuestionError.unsupported }
            let parent = try ScopedFolderDescriptor(rootURL: parentURL)
            let parentState = try parent.state()
            guard let state = try parent.state(of: selected.lastPathComponent), state.isRegularFile, state.isPlaceholder == false else { throw DocumentQuestionError.unsupported }
            guard (0...20 * 1_024 * 1_024).contains(state.size) else { throw DocumentQuestionError.tooLarge }
            let file = try parent.openFile(selected.lastPathComponent)
            let data = try Self.bytes(file, expected: state)
            let pages: [DocumentPageText]
            if selected.pathExtension.lowercased() == "pdf" {
                pages = try await PDFDocumentTextExtractor(recognizer: textRecognizer).extract(data,
                    fileName: selected.lastPathComponent, remainingOCRPages: remainingOCRPages, progress: progress)
                remainingOCRPages -= pages.filter(\.isOCR).count
            } else {
                guard let text = String(data: data, encoding: .utf8), text.contains("\0") == false else { throw DocumentQuestionError.unreadable }
                guard text.count <= 200_000 else { throw DocumentQuestionError.tooLarge }
                pages = [DocumentPageText(number: nil, text: text)]
            }
            let id = UUID()
            var passages: [DocumentPassage] = []
            for page in pages {
                let text = Self.normalized(page.text)
                totalCharacters += text.count
                guard totalCharacters <= 300_000 else { throw DocumentQuestionError.tooLarge }
                var start = text.startIndex
                while start < text.endIndex {
                    try Task.checkCancellation()
                    let end = text.index(start, offsetBy: 900, limitedBy: text.endIndex) ?? text.endIndex
                    passages.append(DocumentPassage(id: nextID, documentID: id, fileName: selected.lastPathComponent,
                        page: page.number, text: String(text[start..<end]), isOCR: page.isOCR))
                    nextID += 1
                    guard end < text.endIndex else { break }
                    start = text.index(end, offsetBy: -100)
                }
            }
            guard passages.isEmpty == false else { throw DocumentQuestionError.noText }
            documents.append(QuestionDocument(id: id, url: parentURL.appending(path: selected.lastPathComponent),
                parentState: parentState, state: state, passages: passages,
                skippedPageCount: pages.filter { Self.normalized($0.text).isEmpty }.count,
                ocrPageCount: pages.filter { $0.isOCR && Self.normalized($0.text).isEmpty == false }.count))
        }
        try await validate(documents)
        return documents
    }

    @concurrent func validate(_ documents: [QuestionDocument]) async throws {
        for document in documents {
            try Task.checkCancellation()
            do {
                let parent = try ScopedFolderDescriptor(rootURL: document.url.deletingLastPathComponent())
                guard try parent.state().hasSameIdentity(as: document.parentState),
                      try parent.openFile(document.url.lastPathComponent).state() == document.state else { throw DocumentQuestionError.changed }
            } catch is CancellationError { throw CancellationError() }
            catch { throw DocumentQuestionError.changed }
        }
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func bytes(_ file: ScopedFolderDescriptor, expected: ComparedFileState) throws -> Data {
        guard try file.state() == expected else { throw DocumentQuestionError.changed }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            try Task.checkCancellation()
            let length = buffer.withUnsafeMutableBytes { Darwin.read(file.rawValue, $0.baseAddress, $0.count) }
            if length < 0 {
                if errno == EINTR { continue }
                throw DocumentQuestionError.unreadable
            }
            if length == 0 { break }
            guard data.count + length <= expected.size else { throw DocumentQuestionError.changed }
            data.append(contentsOf: buffer.prefix(length))
        }
        guard data.count == expected.size, try file.state() == expected else { throw DocumentQuestionError.changed }
        return data
    }
}
