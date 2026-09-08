import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class DocumentQuestionModel {
    private(set) var selection: [URL] = []
    private(set) var documents: [QuestionDocument] = []
    private(set) var claims: [DocumentAnswerClaim] = []
    private(set) var passages: [DocumentPassage] = []
    private(set) var answeredQuestion: String?
    private(set) var retrievedQuestion: String?
    private(set) var errorMessage: String?
    private(set) var activity: String?
    private(set) var isCancelling = false
    private(set) var isEnabled = true
    var question = ""
    var inspectedClaim: DocumentAnswerClaim?
    @ObservationIgnored private let reader: any DocumentReading
    @ObservationIgnored private let answerer: any DocumentAnswerGenerating
    @ObservationIgnored private var task: Task<Void, Never>?

    init(reader: any DocumentReading = LocalDocumentReader(), answerer: any DocumentAnswerGenerating = FoundationModelsDocumentAnswerer()) {
        self.reader = reader; self.answerer = answerer
    }
    deinit { task?.cancel() }
    var isWorking: Bool { activity != nil }
    var canAsk: Bool { isEnabled && isWorking == false && documents.isEmpty == false && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    func select(_ urls: [URL]) {
        guard isWorking == false else { return }
        clear()
        selection = urls
    }

    func chooseDocuments() {
        guard isWorking == false, isEnabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = LocalDocumentReader.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Select Documents"
        panel.message = "Choose up to 5 documents. Select Read Documents afterward to prepare their text on this Mac."
        panel.begin { [weak self] response in if response == .OK { self?.select(panel.urls) } }
    }

    @discardableResult func readDocuments() -> Task<Void, Never>? {
        guard isEnabled, isWorking == false else { return nil }
        let selected = selection
        guard (1...5).contains(selected.count) else { errorMessage = DocumentQuestionError.selection.localizedDescription; return nil }
        activity = "Reading selected documents on this Mac…"
        errorMessage = nil
        task = Task { [weak self, reader] in
            do {
                let result = try await reader.read(selected)
                try Task.checkCancellation()
                guard let self, isEnabled else { return }
                documents = result
                claims = []; passages = []; answeredQuestion = nil; retrievedQuestion = nil
                finish()
            } catch {
                guard let self else { return }
                recordFailure(error)
                finish()
            }
        }
        return task
    }

    @discardableResult func ask() -> Task<Void, Never>? {
        guard canAsk else { return nil }
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 500, query.utf8.count <= 1_000 else { errorMessage = DocumentQuestionError.invalidQuestion.localizedDescription; return nil }
        let current = documents
        activity = "Finding supporting passages…"
        errorMessage = nil
        task = Task { [weak self, reader, answerer] in
            do {
                try await reader.validate(current)
                let sources = try await DocumentPassageRetriever.retrieve(question: query, documents: current)
                guard sources.isEmpty == false else { throw DocumentQuestionError.noEvidence }
                try Task.checkCancellation()
                self?.activity = "Preparing an on-device answer…"
                self?.passages = sources
                self?.retrievedQuestion = query
                let draft = try await answerer.answer(question: query, sources: sources)
                let verified = try DocumentAnswerValidator.validate(draft, sources: sources)
                try await reader.validate(current)
                try Task.checkCancellation()
                guard let self, isEnabled else { return }
                claims = verified
                answeredQuestion = query
                finish()
            } catch {
                guard let self else { return }
                recordFailure(error)
                finish()
            }
        }
        return task
    }

    @discardableResult func reveal(_ claim: DocumentAnswerClaim, onReveal: @escaping @MainActor (URL) -> Void) -> Task<Void, Never>? {
        guard isWorking == false, let document = documents.first(where: { $0.id == claim.source.documentID }) else { return nil }
        activity = "Checking the source document…"
        task = Task { [weak self, reader] in
            do {
                try await reader.validate([document])
                try Task.checkCancellation()
                guard let self else { return }
                finish(); onReveal(document.url)
            } catch {
                guard let self else { return }
                recordFailure(error)
                finish()
            }
        }
        return task
    }

    func cancel() { if isWorking { isCancelling = true; task?.cancel() } }
    func clear() {
        cancel()
        documents = []; claims = []; passages = []; selection = []; question = ""; answeredQuestion = nil; retrievedQuestion = nil; inspectedClaim = nil; errorMessage = nil
    }
    func setEnabled(_ enabled: Bool) { isEnabled = enabled; if enabled == false { clear() } }

    private func recordFailure(_ error: any Error) {
        guard Task.isCancelled == false else { return }
        errorMessage = DocumentQuestionError.message(for: error)
        if error as? DocumentQuestionError == .changed {
            documents = []; claims = []; passages = []; answeredQuestion = nil; retrievedQuestion = nil; inspectedClaim = nil
        }
    }
    private func finish() { task = nil; activity = nil; isCancelling = false }
}
