import Foundation
import Testing
@testable import FinallyExplorer

struct LocalDocumentReaderTests {
    @Test("Read only the chosen documents, preserving PDF page references and source files")
    func extraction() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let text = try fixture.write("Invoice.txt", "The payment deadline is 30 September 2026.")
        let pdf = fixture.source.appending(path: "Invoice.pdf")
        let pdfData = try DocumentQuestionFixtures.pdf(pages: ["Invoice 4827", "The payment deadline is 30 September 2026."])
        try pdfData.write(to: pdf)
        let documents = try await LocalDocumentReader().read([text, pdf])
        #expect(documents.count == 2)
        #expect(documents[0].passages[0].text.contains("30 September"))
        #expect(documents[1].passages.contains { $0.page == 2 && $0.text.contains("30 September") })
        #expect(Set(documents.flatMap(\.passages).map(\.id)).count == documents.flatMap(\.passages).count)
        #expect(try Data(contentsOf: pdf) == pdfData)
    }

    @Test("Invalid selection, malformed PDF, symlinks, and oversized text fail explicitly")
    func boundaries() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Document.txt", "The payment deadline is tomorrow.")
        let reader = LocalDocumentReader()
        await #expect(throws: DocumentQuestionError.selection) { try await reader.read([]) }
        await #expect(throws: DocumentQuestionError.selection) { try await reader.read([file, file]) }
        let broken = try fixture.write("Broken.pdf", "not a PDF")
        await #expect(throws: DocumentReadFailure(fileName: "Broken.pdf", reason: .invalidPDF)) { try await reader.read([broken]) }
        let link = fixture.source.appending(path: "Link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        await #expect(throws: DocumentReadFailure(fileName: "Link.txt", reason: .linkedFile)) { try await reader.read([link]) }
        let large = try fixture.write("Large.txt", String(repeating: "x", count: 200_001))
        await #expect(throws: DocumentReadFailure(fileName: "Large.txt", reason: .textLimit)) { try await reader.read([large]) }
        let empty = try fixture.write("Empty.txt", "  \n ")
        await #expect(throws: DocumentReadFailure(fileName: "Empty.txt", reason: .noText)) { try await reader.read([empty]) }
    }

    @Test("Changed or replaced sources cannot be used for answers", arguments: [false, true])
    func changed(_ linkSwap: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Document.txt", "Payment deadline is Friday.")
        let reader = LocalDocumentReader()
        let documents = try await reader.read([file])
        if linkSwap {
            let moved = fixture.destination.appending(path: "Document.txt")
            try FileManager.default.moveItem(at: file, to: moved)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: moved)
        } else { try Data("Changed deadline".utf8).write(to: file) }
        await #expect(throws: DocumentQuestionError.changed) { try await reader.validate(documents) }
    }

    @Test("Retrieval is bounded and never treats a filename as supporting evidence")
    func retrieval() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Invoice.txt", String(repeating: "Payment deadline is 30 September 2026. ", count: 100))
        let docs = try await LocalDocumentReader().read([file])
        let passages = try await DocumentPassageRetriever.retrieve(question: "What is the payment deadline?", documents: docs)
        #expect(passages.count <= 4)
        #expect(passages.allSatisfy { $0.text.utf8.count <= 600 })
        #expect(try await DocumentPassageRetriever.retrieve(question: "invoice", documents: docs).isEmpty)
    }

    @Test("Byte, PDF page and total extracted text limits are enforced before answering")
    func extractionLimits() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let reader = LocalDocumentReader()
        let oversized = fixture.source.appending(path: "Oversized.txt")
        try Data(repeating: 65, count: 20 * 1_024 * 1_024 + 1).write(to: oversized)
        await #expect(throws: DocumentReadFailure(fileName: "Oversized.txt", reason: .fileSizeLimit)) { try await reader.read([oversized]) }
        let pdf = fixture.source.appending(path: "TooManyPages.pdf")
        try DocumentQuestionFixtures.pdf(pages: Array(repeating: "Payment deadline is Friday.", count: 101)).write(to: pdf)
        await #expect(throws: DocumentReadFailure(fileName: "TooManyPages.pdf", reason: .pdfPageLimit(101))) { try await reader.read([pdf]) }
        let first = try fixture.write("First.txt", String(repeating: "a", count: 150_001))
        let second = try fixture.write("Second.txt", String(repeating: "b", count: 150_001))
        await #expect(throws: DocumentReadFailure(fileName: "Second.txt", reason: .totalTextLimit)) { try await reader.read([first, second]) }
        let invalidUTF8 = fixture.source.appending(path: "Invalid.txt")
        try Data([0xff, 0xfe, 0x00]).write(to: invalidUTF8)
        await #expect(throws: DocumentReadFailure(fileName: "Invalid.txt", reason: .unsupportedTextEncoding)) { try await reader.read([invalidUTF8]) }
    }
}
