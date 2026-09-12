import Foundation
import PDFKit

nonisolated struct PDFDocumentTextExtractor: Sendable {
    let recognizer: any DocumentTextRecognizing

    @concurrent func extract(_ data: Data, fileName: String, remainingOCRPages: Int,
                            progress: @escaping @Sendable (DocumentReadProgress) async -> Void) async throws -> [DocumentPageText] {
        try Task.checkCancellation()
        guard let pdf = PDFDocument(data: data), pdf.isLocked == false else { throw DocumentQuestionError.unreadable }
        guard pdf.pageCount <= 100 else { throw DocumentQuestionError.tooLarge }
        var pages: [DocumentPageText] = []
        var characters = 0, ocrPages = 0
        // Check this PDF's page/text budget before starting expensive OCR.
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { throw DocumentQuestionError.unreadable }
            guard page.numberOfCharacters <= 200_000 - characters else { throw DocumentQuestionError.tooLarge }
            let text = page.string ?? ""
            characters += text.count
            guard characters <= 200_000 else { throw DocumentQuestionError.tooLarge }
            let needsOCR = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if needsOCR { ocrPages += 1 }
            guard ocrPages <= remainingOCRPages else { throw DocumentQuestionError.ocrLimit }
            pages.append(DocumentPageText(number: index + 1, text: text, isOCR: needsOCR))
        }
        // One page at a time: PDFKit state and raster buffers are not shared
        // with concurrent workers. Only recognized strings leave this task.
        for index in pages.indices where pages[index].isOCR {
            try Task.checkCancellation()
            await progress(DocumentReadProgress(fileName: fileName, page: index + 1, pageCount: pages.count))
            try Task.checkCancellation()
            guard let page = pdf.page(at: index)?.pageRef else { throw DocumentQuestionError.unreadable }
            let image = try PDFPageRasterizer.image(page)
            let text = try await recognizer.recognize(image)
            try Task.checkCancellation()
            guard text.count <= 20_000 else { throw DocumentQuestionError.ocrLimit }
            characters += text.count
            guard characters <= 200_000 else { throw DocumentQuestionError.tooLarge }
            pages[index].text = text
        }
        return pages
    }
}
