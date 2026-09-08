import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import FinallyExplorer

nonisolated enum DocumentQuestionFixtures {
    static func pdf(pages: [String]) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for text in pages {
            context.beginPDFPage(nil)
            let line = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 30, y: 650)
            CTLineDraw(CTLineCreateWithAttributedString(line), context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

nonisolated struct QuotingDocumentAnswerer: DocumentAnswerGenerating {
    func answer(question: String, sources: [DocumentPassage]) async throws -> DocumentAnswerDraft {
        let source = try #require(sources.first)
        return DocumentAnswerDraft(insufficientEvidence: false, claims: [.init(statement: "The document states the payment deadline.", sourceID: source.id, quote: String(source.text.prefix(150)))])
    }
}

nonisolated struct PausedDocumentAnswerer: DocumentAnswerGenerating {
    let gate: FolderComparisonTestGate
    func answer(question: String, sources: [DocumentPassage]) async throws -> DocumentAnswerDraft {
        await gate.pause()
        return try await QuotingDocumentAnswerer().answer(question: question, sources: sources)
    }
}

nonisolated struct PausedDocumentReader: DocumentReading {
    let gate: FolderComparisonTestGate
    func read(_ urls: [URL]) async throws -> [QuestionDocument] {
        let documents = try await LocalDocumentReader().read(urls)
        await gate.pause()
        return documents
    }
    func validate(_ documents: [QuestionDocument]) async throws {
        try await LocalDocumentReader().validate(documents)
    }
}
