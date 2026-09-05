import Foundation

nonisolated struct TextFilePreview: Equatable, Sendable {
    let text: String
    let isTruncated: Bool
}

nonisolated enum TextFilePreviewError: LocalizedError {
    case notText
    case notRegularFile

    var errorDescription: String? {
        switch self {
        case .notText:
            "This file could not be read as text. Open it in its default app."
        case .notRegularFile:
            "This item is not a readable text file."
        }
    }
}

nonisolated struct TextFilePreviewService: Sendable {
    static let maximumByteCount = 256 * 1_024

    static func supports(_ item: FileItem) -> Bool {
        guard item.isDirectory == false, item.isImage == false else { return false }
        let kind = FileItemIconResolver.kind(for: item)
        if kind == .sourceCode || kind == .text { return true }
        return ["csv", "tsv", "log", "ini", "conf", "config", "plist"]
            .contains(item.url.pathExtension.lowercased())
            || ["readme", "license", "makefile", "dockerfile", ".gitignore",
                ".gitattributes", ".env", ".zshrc", ".bashrc", ".editorconfig"]
                .contains(item.name.lowercased())
    }

    /// Reads a bounded prefix on the concurrent executor, never the UI thread.
    @concurrent
    func load(_ url: URL) async throws -> TextFilePreview {
        try Task.checkCancellation()
        let metadata = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard metadata.isRegularFile == true else {
            throw TextFilePreviewError.notRegularFile
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: Self.maximumByteCount + 1) ?? Data()
        try Task.checkCancellation()

        let isTruncated = data.count > Self.maximumByteCount
        let prefix = Data(data.prefix(Self.maximumByteCount))
        let text = try Self.decode(prefix, isTruncated: isTruncated)
        try Task.checkCancellation()
        return TextFilePreview(text: text, isTruncated: isTruncated)
    }

    private static func decode(_ data: Data, isTruncated: Bool) throws -> String {
        let encoding: String.Encoding
        let byteOrderMarkLength: Int
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            encoding = .utf32LittleEndian
            byteOrderMarkLength = 4
        } else if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            encoding = .utf32BigEndian
            byteOrderMarkLength = 4
        } else if data.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian
            byteOrderMarkLength = 2
        } else if data.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian
            byteOrderMarkLength = 2
        } else {
            encoding = .utf8
            byteOrderMarkLength = data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        }
        let payload = Data(data.dropFirst(byteOrderMarkLength))
        // A bounded read may end in the middle of a Unicode scalar. Only trim
        // that incomplete tail; invalid bytes elsewhere must remain an error.
        for tailLength in 0...(isTruncated ? min(3, payload.count) : 0) {
            if let text = String(data: payload.dropLast(tailLength), encoding: encoding),
               text.unicodeScalars.contains(where: { $0.value == 0 }) == false {
                return text
            }
        }
        throw TextFilePreviewError.notText
    }
}
