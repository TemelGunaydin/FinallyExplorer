import Foundation
import Testing
@testable import FinallyExplorer

@MainActor struct DocumentQuestionModelTests {
    @Test("Selection is read-free; explicit reading and asking publish sourced answers")
    func lifecycle() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is 30 September 2026.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer())
        model.select([file])
        #expect(model.documents.isEmpty)
        #expect(model.canAsk == false)
        await model.readDocuments()?.value
        #expect(model.documents.count == 1)
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        #expect(model.claims.count == 1)
        #expect(model.claims[0].source.fileName == "Report.txt")
        #expect(model.errorMessage == nil)
        model.clear()
        #expect(model.documents.isEmpty)
        #expect(model.claims.isEmpty)
        #expect(model.passages.isEmpty)
        #expect(model.question.isEmpty)
    }

    @Test("Clear/opt-out prevent a late answer and hold the busy gate until cancellation unwinds", .timeLimit(.minutes(1)), arguments: [false, true])
    func cancel(_ optOut: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let gate = FolderComparisonTestGate()
        let model = DocumentQuestionModel(answerer: PausedDocumentAnswerer(gate: gate))
        model.select([file]); await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        let task = try #require(model.ask())
        await gate.waitUntilEntered()
        if optOut { model.setEnabled(false) } else { model.clear() }
        #expect(model.isWorking)
        #expect(model.ask() == nil)
        await gate.release(); await task.value
        #expect(model.isWorking == false)
        #expect(model.claims.isEmpty)
        #expect(model.documents.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("Changing a source while the model is answering discards the answer", .timeLimit(.minutes(1)))
    func sourceChangesDuringAnswer() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let gate = FolderComparisonTestGate()
        let model = DocumentQuestionModel(answerer: PausedDocumentAnswerer(gate: gate))
        model.select([file]); await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        let task = try #require(model.ask())
        await gate.waitUntilEntered()
        try Data("The deadline changed.".utf8).write(to: file)
        await gate.release(); await task.value
        #expect(model.documents.isEmpty)
        #expect(model.claims.isEmpty)
        #expect(model.errorMessage == DocumentQuestionError.changed.localizedDescription)
    }

    @Test("A question with no matching passages does not invent an answer")
    func noEvidence() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer())
        model.select([file]); await model.readDocuments()?.value
        model.question = "What is the spaceship velocity?"
        await model.ask()?.value
        #expect(model.claims.isEmpty)
        #expect(model.errorMessage == DocumentQuestionError.noEvidence.localizedDescription)
    }

    @Test("Clearing while reading prevents text from reappearing", .timeLimit(.minutes(1)))
    func cancelRead() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let gate = FolderComparisonTestGate()
        let model = DocumentQuestionModel(reader: PausedDocumentReader(gate: gate))
        model.select([file])
        let task = try #require(model.readDocuments())
        await gate.waitUntilEntered()
        model.clear()
        #expect(model.isWorking)
        #expect(model.readDocuments() == nil)
        await gate.release()
        await task.value
        #expect(model.documents.isEmpty)
        #expect(model.selection.isEmpty)
        #expect(model.isWorking == false)
        #expect(model.errorMessage == nil)
    }

    @Test("Revealing a changed source clears stale answers and does not navigate")
    func sourceReveal() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer())
        model.select([file]); await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        let claim = try #require(model.claims.first)
        var revealed: URL?
        await model.reveal(claim) { revealed = $0 }?.value
        #expect(revealed == file)
        revealed = nil
        try Data("The payment deadline changed.".utf8).write(to: file)
        await model.reveal(claim) { revealed = $0 }?.value
        #expect(revealed == nil)
        #expect(model.claims.isEmpty)
        #expect(model.documents.isEmpty)
        #expect(model.errorMessage == DocumentQuestionError.changed.localizedDescription)
    }

    @Test("Failed retrieval keeps the previous answer visibly tied to its original question")
    func previousAnswer() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "The payment deadline is Friday.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer())
        model.select([file]); await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        let previous = model.claims.map(\.id)
        model.question = "What is the spaceship velocity?"
        await model.ask()?.value
        #expect(model.claims.map(\.id) == previous)
        #expect(model.answeredQuestion == "What is the payment deadline?")
        #expect(model.retrievedQuestion == "What is the payment deadline?")
        #expect(model.errorMessage == DocumentQuestionError.noEvidence.localizedDescription)
    }

    @Test("Selecting different documents forgets the old answer and requires reading again")
    func changeSelection() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let first = try fixture.write("First.txt", "The payment deadline is Friday.")
        let second = try fixture.write("Second.txt", "The invoice total is 480 USD.")
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer())
        model.select([first]); await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        #expect(model.claims.isEmpty == false)
        model.select([second])
        #expect(model.selection == [second])
        #expect(model.documents.isEmpty)
        #expect(model.claims.isEmpty)
        #expect(model.passages.isEmpty)
        #expect(model.canAsk == false)
    }
}
