import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import FinallyExplorer

struct PDFDocumentOCRTests {
    @Test("Cropped and rotated PDFs fill the raster instead of shrinking into its center", arguments: [0, 90, 180, 270])
    func cropAndScale(_ rotation: Int) throws {
        let pdf = try #require(PDFDocument(data: DocumentOCRFixtures.croppedMarkerPDF(rotation: rotation)))
        let page = try #require(pdf.page(at: 0)?.pageRef)
        let image = try PDFPageRasterizer.image(page)
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(image.bitsPerPixel == 32)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * image.bytesPerRow + x * 4
                if bytes[offset] < 32 && bytes[offset + 1] < 32 && bytes[offset + 2] < 32 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let rotated = rotation == 90 || rotation == 270
        #expect(image.width == (rotated ? 1_200 : 900))
        #expect(image.height == (rotated ? 900 : 1_200))
        #expect(abs(maxX - minX + 1 - (rotated ? 240 : 300)) <= 2)
        #expect(abs(maxY - minY + 1 - (rotated ? 300 : 240)) <= 2)
    }

    @Test("Real Vision reads an image-only PDF page and keeps its page and OCR provenance", .timeLimit(.minutes(1)))
    func mixedDocument() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let data = try DocumentOCRFixtures.pdf(scannedPages: [
            "Harbor Studio invoice 4827\nPayment deadline is 30 September 2026.", ""
        ], embeddedFirstPage: "Invoice cover sheet")
        let file = fixture.source.appending(path: "Scan.pdf")
        try data.write(to: file)
        let pdf = try #require(PDFDocument(data: data))
        let page = try #require(pdf.page(at: 1)?.pageRef)
        try DocumentOCRFixtures.recordImage(PDFPageRasterizer.image(page), name: "ScannedPage")
        let recorder = DocumentReadProgressRecorder()
        let documents = try await LocalDocumentReader().read([file]) { await recorder.record($0) }
        let document = try #require(documents.first)
        #expect(document.ocrPageCount == 1)
        #expect(document.skippedPageCount == 1)
        #expect(document.passages.first?.isOCR == false)
        let scanned = try #require(document.passages.first { $0.page == 2 })
        #expect(scanned.isOCR)
        #expect(scanned.text.contains("30 September 2026"), "\(scanned.text)")
        #expect(scanned.sourceLabel == "Scan.pdf · page 2 · OCR")
        #expect(await recorder.values.map(\.page) == [2, 3])
        #expect(await recorder.values.allSatisfy { $0.pageCount == 3 && $0.fileName == "Scan.pdf" })
        let search = LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder())
        let index = try await search.prepare(documents)
        let result = try await search.retrieve(question: "payment deadline", index: index)
        #expect(result.passages.first?.isOCR == true)
        #expect(result.passages.first?.page == 2)
        let keywords = try await DocumentPassageRetriever.retrieve(question: "payment deadline", documents: documents)
        #expect(keywords.first?.isOCR == true)
        let draft = DocumentAnswerDraft(insufficientEvidence: false,
            claims: [.init(statement: "30 September 2026", sourceID: scanned.id, quote: "30 September 2026")])
        let claim = try #require(DocumentAnswerValidator.validate(draft, sources: [scanned]).first)
        #expect(claim.source.isOCR && claim.source.page == 2)
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("Native text never invokes OCR")
    func nativeText() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Native.pdf")
        try DocumentQuestionFixtures.pdf(pages: ["The payment deadline is Friday."]).write(to: file)
        let text = try fixture.write("Note.txt", "Plain text does not need OCR.")
        let recognizer = RecordingDocumentTextRecognizer(error: .ocrFailed)
        let documents = try await LocalDocumentReader(textRecognizer: recognizer).read([file, text])
        #expect(await recognizer.calls == 0)
        #expect(documents.allSatisfy { $0.ocrPageCount == 0 && $0.passages.allSatisfy { $0.isOCR == false } })
    }

    @Test("Rasterization honors page rotation and bounds its pixel allocation", arguments: [0, 90, 180, 270])
    func rotatedRaster(_ rotation: Int) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Rotated.pdf")
        try DocumentOCRFixtures.pdf(scannedPages: ["Rotated page"], rotation: rotation).write(to: file)
        let recognizer = RecordingDocumentTextRecognizer()
        _ = try await LocalDocumentReader(textRecognizer: recognizer).read([file])
        let dimensions = try #require(await recognizer.dimensions.first)
        #expect(dimensions.width <= 2_400 && dimensions.height <= 2_400)
        #expect(dimensions.width * dimensions.height <= 5_760_000)
        #expect((dimensions.width > dimensions.height) == (rotation == 90 || rotation == 270))
    }

    @Test("Blank scans fail without inventing text", .timeLimit(.minutes(1)))
    func blankScan() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Blank.pdf")
        try DocumentOCRFixtures.pdf(scannedPages: [""]).write(to: file)
        await #expect(throws: DocumentReadFailure(fileName: file.lastPathComponent, reason: .noText)) { try await LocalDocumentReader().read([file]) }
    }
}
