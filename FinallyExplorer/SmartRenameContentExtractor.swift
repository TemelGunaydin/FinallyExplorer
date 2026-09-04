//
//  SmartRenameContentExtractor.swift
//  FinallyExplorer
//

import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

nonisolated struct SmartRenameContentLimits: Equatable, Sendable {
    let maximumCharacterCount: Int
    let maximumTextByteCount: Int
    let maximumPDFPageCount: Int
    let maximumRichContentByteCount: Int
    let maximumImagePixelCount: Int

    init(
        maximumCharacterCount: Int = 3_000,
        maximumTextByteCount: Int = 12_000,
        maximumPDFPageCount: Int = 8,
        maximumRichContentByteCount: Int = 40 * 1_024 * 1_024,
        maximumImagePixelCount: Int = 40_000_000
    ) {
        self.maximumCharacterCount = max(0, maximumCharacterCount)
        self.maximumTextByteCount = max(0, maximumTextByteCount)
        self.maximumPDFPageCount = max(0, maximumPDFPageCount)
        self.maximumRichContentByteCount = max(
            0,
            maximumRichContentByteCount
        )
        self.maximumImagePixelCount = max(0, maximumImagePixelCount)
    }
}

nonisolated enum SmartRenameContentExtractionError: LocalizedError, Sendable {
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            "The PDF content could not be read for Smart Rename."
        }
    }
}

nonisolated protocol SmartRenameContentExtracting: Sendable {
    func snippet(for url: URL) async throws -> String?
}

actor LocalSmartRenameContentExtractor: SmartRenameContentExtracting {
    private nonisolated static let recognizedTextExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "csv", "fish", "go", "h", "hpp",
        "html", "ini", "java", "js", "json", "jsx", "kt", "kts",
        "log", "m", "md", "mm", "py", "rb", "rs", "scss", "sh",
        "sql", "swift", "toml", "ts", "tsx", "txt", "xml", "yaml",
        "yml", "zsh",
    ]

    private let limits: SmartRenameContentLimits

    init(limits: SmartRenameContentLimits = SmartRenameContentLimits()) {
        self.limits = limits
    }

    func snippet(for url: URL) async throws -> String? {
        try Task.checkCancellation()
        guard limits.maximumCharacterCount > 0 else { return nil }

        let resourceValues = try? url.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard resourceValues?.isRegularFile == true,
              resourceValues?.isSymbolicLink != true else {
            return nil
        }

        let pathExtension = url.pathExtension.lowercased()
        let contentType = UTType(filenameExtension: pathExtension)

        if pathExtension == "pdf" || contentType?.conforms(to: .pdf) == true {
            guard isWithinRichContentLimit(resourceValues?.fileSize) else {
                return nil
            }
            return try pdfSnippet(for: url)
        }

        if contentType?.conforms(to: .image) == true {
            guard isWithinRichContentLimit(resourceValues?.fileSize),
                  imageIsWithinPixelLimit(url) else {
                return nil
            }
            return try await imageSnippet(for: url)
        }

        if contentType?.conforms(to: .text) == true
            || contentType?.conforms(to: .sourceCode) == true
            || Self.recognizedTextExtensions.contains(pathExtension) {
            return try textSnippet(for: url)
        }

        return nil
    }

    private func pdfSnippet(for url: URL) throws -> String? {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url) else {
            throw SmartRenameContentExtractionError.unreadablePDF
        }

        var snippet = ""
        let pageCount = min(document.pageCount, limits.maximumPDFPageCount)

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()
            guard let pageText = document.page(at: pageIndex)?.string,
                  pageText.isEmpty == false else {
                continue
            }

            append(pageText, to: &snippet)
            if snippet.count >= limits.maximumCharacterCount {
                break
            }
        }

        try Task.checkCancellation()
        return normalized(snippet)
    }

    private func textSnippet(for url: URL) throws -> String? {
        try Task.checkCancellation()

        let byteLimit = min(
            limits.maximumTextByteCount,
            limits.maximumCharacterCount * 4
        )
        guard byteLimit > 0 else { return nil }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let data = try fileHandle.read(upToCount: byteLimit) ?? Data()
        try Task.checkCancellation()

        return normalized(
            String(decoding: data, as: UTF8.self)
        )
    }

    private func imageSnippet(for url: URL) async throws -> String? {
        try Task.checkCancellation()

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: url)
        try Task.checkCancellation()

        var snippet = ""
        for observation in observations {
            try Task.checkCancellation()
            guard let text = observation.topCandidates(1).first?.string,
                  text.isEmpty == false else {
                continue
            }

            append(text, to: &snippet)
            if snippet.count >= limits.maximumCharacterCount {
                break
            }
        }

        try Task.checkCancellation()
        return normalized(snippet)
    }

    private func append(_ content: String, to snippet: inout String) {
        let remainingCount = limits.maximumCharacterCount - snippet.count
        guard remainingCount > 0 else { return }

        if snippet.isEmpty == false {
            snippet.append("\n")
        }
        snippet.append(contentsOf: content.prefix(remainingCount))

        if snippet.count > limits.maximumCharacterCount {
            snippet = String(snippet.prefix(limits.maximumCharacterCount))
        }
    }

    private func normalized(_ snippet: String) -> String? {
        let boundedSnippet = String(
            snippet.prefix(limits.maximumCharacterCount)
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return boundedSnippet.isEmpty ? nil : boundedSnippet
    }

    private func isWithinRichContentLimit(_ fileSize: Int?) -> Bool {
        guard limits.maximumRichContentByteCount > 0,
              let fileSize else {
            return false
        }
        return fileSize <= limits.maximumRichContentByteCount
    }

    private func imageIsWithinPixelLimit(_ url: URL) -> Bool {
        guard limits.maximumImagePixelCount > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?
                  .int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?
                  .int64Value,
              width > 0,
              height > 0 else {
            return false
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(
            by: height
        )
        return overflow == false
            && pixelCount <= Int64(limits.maximumImagePixelCount)
    }
}
