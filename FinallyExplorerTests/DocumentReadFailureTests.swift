import Darwin
import Foundation
import PDFKit
import Testing
@testable import FinallyExplorer

struct DocumentReadFailureTests {
    @Test("A 416-page PDF explains the actual page count before OCR starts")
    func longPDF() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Long.pdf")
        let original = try DocumentQuestionFixtures.pdf(pages: Array(repeating: "", count: 416))
        try original.write(to: file)
        let recognizer = RecordingDocumentTextRecognizer()
        let failure = DocumentReadFailure(fileName: "Long.pdf", reason: .pdfPageLimit(416))
        await #expect(throws: failure) { try await LocalDocumentReader(textRecognizer: recognizer).read([file]) }
        #expect(failure.localizedDescription == "Long.pdf\nThis PDF has 416 pages; the limit is 100. Choose a shorter PDF or export just the pages you need.")
        #expect(await recognizer.calls == 0)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test("Password-protected PDFs are distinguished from malformed PDFs")
    func lockedPDF() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Locked.pdf")
        let pdf = try #require(PDFDocument(data: DocumentQuestionFixtures.pdf(pages: ["Private invoice"])))
        let data = try #require(pdf.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "test-password",
            PDFDocumentWriteOption.ownerPasswordOption: "test-owner",
        ]))
        #expect(try #require(PDFDocument(data: data)).isLocked)
        try data.write(to: file)
        await #expect(throws: DocumentReadFailure(fileName: "Locked.pdf", reason: .passwordProtected)) {
            try await LocalDocumentReader().read([file])
        }
    }

    @Test("Reading a known document does not require listing its parent directory")
    func parentSearchOnly() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Selected.txt", "Payment is due Friday.")
        #expect(chmod(fixture.source.path, 0o100) == 0)
        defer { _ = chmod(fixture.source.path, 0o700) }
        // A POSIX permissions regression, not a substitute for native picker QA.
        let listing = Darwin.open(fixture.source.path, O_RDONLY | O_DIRECTORY)
        let listingError = errno
        if listing >= 0 { Darwin.close(listing) }
        #expect(listing == -1 && listingError == EACCES)
        let reader = LocalDocumentReader()
        let documents = try await reader.read([file])
        #expect(documents.first?.passages.first?.text == "Payment is due Friday.")
        try await reader.validate(documents)
    }

    @Test("Missing files and denied read permissions have different recovery messages", arguments: [false, true])
    func fileAccess(_ denied: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Selected.txt", "Payment is due Friday.")
        if denied { #expect(chmod(file.path, 0) == 0) }
        else { try FileManager.default.removeItem(at: file) }
        defer { if denied { _ = chmod(file.path, 0o600) } }
        await #expect(throws: DocumentReadFailure(fileName: "Selected.txt", reason: denied ? .accessDenied : .missing)) {
            try await LocalDocumentReader().read([file])
        }
    }

    @Test("Parent replacement invalidates a previously read document even when its inode survives")
    func changedParent() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Selected.txt", "Payment is due Friday.")
        let reader = LocalDocumentReader()
        let documents = try await reader.read([file])
        let moved = fixture.root.appending(path: "Moved")
        try FileManager.default.moveItem(at: fixture.source, to: moved)
        try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: moved.appending(path: file.lastPathComponent), to: file)
        await #expect(throws: DocumentQuestionError.changed) { try await reader.validate(documents) }
    }

    @MainActor @Test("Losing file permission explains access recovery and clears stale answers")
    func lostPermission() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Selected.txt", "Payment is due Friday.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer(),
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select([file])
        await model.readDocuments()?.value
        model.question = "When is payment due?"
        await model.ask()?.value
        #expect(model.claims.isEmpty == false)
        #expect(chmod(file.path, 0) == 0)
        defer { _ = chmod(file.path, 0o600) }
        await model.ask()?.value
        #expect(model.errorMessage == DocumentReadFailure(fileName: "Selected.txt", reason: .accessDenied).localizedDescription)
        #expect(model.documents.isEmpty && model.retrievalIndex == nil)
        #expect(model.claims.isEmpty && model.history.isEmpty && model.passages.isEmpty)
    }

    @Test("POSIX failures are classified without exposing paths", arguments: [EACCES, EPERM, ENOENT, ENOTDIR, EIO])
    func systemFailure(_ code: Int32) throws {
        let expected: DocumentQuestionError = switch code {
        case EACCES, EPERM: .accessDenied
        case ENOENT, ENOTDIR: .missing
        default: .unreadable
        }
        let error = FolderComparisonError.fileSystem("/private/user/document.pdf", code)
        #expect(DocumentQuestionError.readReason(for: error) == expected)
        #expect(DocumentQuestionError.message(for: error) == expected.localizedDescription)
        let posixCode = try #require(POSIXErrorCode(rawValue: code))
        #expect(DocumentQuestionError.readReason(for: POSIXError(posixCode)) == expected)
    }

    @Test("Cocoa permission errors are not presented as password or damaged-PDF errors")
    func cocoaFailure() {
        #expect(DocumentQuestionError.readReason(for: CocoaError(.fileReadNoPermission)) == .accessDenied)
        #expect(DocumentQuestionError.readReason(for: CocoaError(.fileReadNoSuchFile)) == .missing)
        #expect(DocumentQuestionError.readReason(for: CocoaError(.fileReadUnknown)) == .unreadable)
    }

    @MainActor @Test("Read failures identify the failed document without publishing partial context")
    func modelMessage() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let readable = try fixture.write("First.txt", "Payment is due Friday.")
        let broken = try fixture.write("Broken.pdf", "not a PDF")
        let model = DocumentQuestionModel(search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select([readable, broken])
        await model.readDocuments()?.value
        #expect(model.errorMessage == DocumentReadFailure(fileName: "Broken.pdf", reason: .invalidPDF).localizedDescription)
        #expect(model.documents.isEmpty && model.retrievalIndex == nil && model.isWorking == false)
        model.select([readable])
        await model.readDocuments()?.value
        #expect(model.errorMessage == nil && model.documents.count == 1)
    }
}
