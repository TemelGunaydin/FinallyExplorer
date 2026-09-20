import Foundation
import Testing
@testable import FinallyExplorer

struct DocumentOCRSafetyTests {
    @Test("Exactly twenty OCR pages remain supported")
    func pageBudgetBoundary() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Twenty.pdf")
        try DocumentQuestionFixtures.pdf(pages: Array(repeating: "", count: 20)).write(to: file)
        let recognizer = RecordingDocumentTextRecognizer()
        let documents = try await LocalDocumentReader(textRecognizer: recognizer).read([file])
        #expect(await recognizer.calls == 20)
        #expect(documents.first?.ocrPageCount == 20)
        #expect(documents.first?.passages.map(\.page) == Array(1...20).map(Optional.some))
    }

    @Test("OCR and native text share the total selection text budget")
    func aggregateTextBudget() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let text = try fixture.write("Native.txt", String(repeating: "a", count: 200_000))
        let scan = fixture.source.appending(path: "Dense.pdf")
        try DocumentQuestionFixtures.pdf(pages: Array(repeating: "", count: 6)).write(to: scan)
        let recognizer = RecordingDocumentTextRecognizer(text: String(repeating: "b", count: 19_000))
        await #expect(throws: DocumentReadFailure(fileName: "Dense.pdf", reason: .totalTextLimit)) {
            try await LocalDocumentReader(textRecognizer: recognizer).read([text, scan])
        }
    }

    @Test("OCR page limits are checked before recognizing a large PDF")
    func pageBudget() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Many.pdf")
        try DocumentQuestionFixtures.pdf(pages: Array(repeating: "", count: 21)).write(to: file)
        let recognizer = RecordingDocumentTextRecognizer()
        await #expect(throws: DocumentReadFailure(fileName: "Many.pdf", reason: .ocrLimit)) { try await LocalDocumentReader(textRecognizer: recognizer).read([file]) }
        #expect(await recognizer.calls == 0)
    }

    @Test("The OCR page budget applies across the entire selection")
    func selectionBudget() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        var files: [URL] = []
        for name in ["First.pdf", "Second.pdf"] {
            let file = fixture.source.appending(path: name)
            try DocumentQuestionFixtures.pdf(pages: [""]).write(to: file)
            files.append(file)
        }
        let recognizer = RecordingDocumentTextRecognizer()
        await #expect(throws: DocumentReadFailure(fileName: "Second.pdf", reason: .ocrLimit)) {
            try await LocalDocumentReader(textRecognizer: recognizer, maximumOCRPages: 1).read(files)
        }
        #expect(await recognizer.calls == 1)
    }

    @Test("OCR text remains inside per-page and per-file limits", arguments: [false, true])
    func textBudget(_ fileLimit: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Dense.pdf")
        try DocumentQuestionFixtures.pdf(pages: Array(repeating: "", count: fileLimit ? 11 : 1)).write(to: file)
        let recognizer = RecordingDocumentTextRecognizer(text: String(repeating: "x", count: fileLimit ? 19_000 : 20_001))
        await #expect(throws: DocumentReadFailure(fileName: "Dense.pdf", reason: fileLimit ? .textLimit : .ocrLimit)) {
            try await LocalDocumentReader(textRecognizer: recognizer).read([file])
        }
    }

    @Test("The OCR deadline cancels cooperative work", .timeLimit(.minutes(1)))
    func deadline() async throws {
        await #expect(throws: DocumentQuestionError.ocrTimedOut) {
            try await VisionDocumentTextRecognizer.bounded(timeout: .zero) {
                // A cancellable stand-in for pending Vision work, not a test delay.
                try await Task.sleep(for: .seconds(60))
                return "Must not be returned"
            }
        }
    }

    @MainActor @Test("Clearing or opting out during OCR discards late text and progress", .timeLimit(.minutes(1)), arguments: [false, true])
    func cancelRead(_ optOut: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Scan.pdf")
        try DocumentQuestionFixtures.pdf(pages: [""]).write(to: file)
        let gate = FolderComparisonTestGate()
        let recognizer = RecordingDocumentTextRecognizer(gate: gate)
        let model = DocumentQuestionModel(reader: LocalDocumentReader(textRecognizer: recognizer),
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select([file])
        #expect(await recognizer.calls == 0, "Selecting a scan must not perform OCR")
        let work = try #require(model.readDocuments())
        await gate.waitUntilEntered()
        #expect(model.activity == "Recognizing text in Scan.pdf · page 1 of 1…")
        if optOut { model.setEnabled(false) } else { model.clear() }
        #expect(model.isWorking && model.isCancelling)
        #expect(model.readDocuments() == nil)
        await gate.release(); await work.value
        #expect(model.documents.isEmpty && model.retrievalIndex == nil)
        #expect(model.history.isEmpty && model.passages.isEmpty)
        #expect(model.isWorking == false && model.activity == nil && model.errorMessage == nil)
    }

    @MainActor @Test("Changing a PDF during OCR rejects the extracted snapshot", .timeLimit(.minutes(1)))
    func changedSource() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = fixture.source.appending(path: "Scan.pdf")
        try DocumentQuestionFixtures.pdf(pages: [""]).write(to: file)
        let gate = FolderComparisonTestGate()
        let model = DocumentQuestionModel(reader: LocalDocumentReader(textRecognizer: RecordingDocumentTextRecognizer(gate: gate)))
        model.select([file]); let work = try #require(model.readDocuments())
        await gate.waitUntilEntered()
        try Data("Changed PDF".utf8).write(to: file)
        await gate.release(); await work.value
        #expect(model.errorMessage == DocumentQuestionError.changed.localizedDescription)
        #expect(model.documents.isEmpty && model.retrievalIndex == nil)
    }

    @MainActor @Test("A recognition failure never publishes a partially read selection")
    func noPartialContext() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let first = try fixture.write("First.txt", "The first document is readable.")
        let scan = fixture.source.appending(path: "Scan.pdf")
        try DocumentQuestionFixtures.pdf(pages: [""]).write(to: scan)
        let model = DocumentQuestionModel(reader: LocalDocumentReader(textRecognizer: RecordingDocumentTextRecognizer(error: .ocrFailed)))
        model.select([first, scan]); await model.readDocuments()?.value
        #expect(model.errorMessage == DocumentReadFailure(fileName: "Scan.pdf", reason: .ocrFailed).localizedDescription)
        #expect(model.documents.isEmpty && model.retrievalIndex == nil)
    }
}
