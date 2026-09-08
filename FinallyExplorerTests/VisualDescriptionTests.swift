import Foundation
import FoundationModels
import Testing
@testable import FinallyExplorer

struct VisualDescriptionTests {
    @Test("Seaside sentences map to OR synonyms without a model", arguments: ["Find photos taken by the sea", "Show me my beach photos", "Pictures near the seaside", "Find photos at the beach"])
    func seaside(_ query: String) async throws {
        let plan = try await FoundationModelsVisualInterpreter().interpret(query)
        #expect(plan.concepts.count == 1)
        #expect(plan.concepts[0].contains("beach"))
        #expect(plan.concepts[0].contains("sea"))
    }

    @Test("Unsupported dates/actions are never discarded", arguments: ["Find beach photos from yesterday", "Find photos by the sea without people", "Delete beach photos", "Find beach photos from 2020"])
    func rejectUnsupported(_ query: String) async {
        await #expect(throws: VisualDescriptionError.unsupportedRequest) { try await FoundationModelsVisualInterpreter().interpret(query) }
    }

    @Test("Routing preserves explicit filename and date-only searches")
    func routing() {
        #expect(VisualDescriptionRouting.isVisualRequest("Find photos taken by the sea"))
        #expect(VisualDescriptionRouting.isVisualRequest("Show my seaside pictures"))
        #expect(VisualDescriptionRouting.isVisualRequest("Photos taken three days ago") == false)
        #expect(VisualDescriptionRouting.isVisualRequest("Photos named beach") == false)
        #expect(VisualDescriptionRouting.isVisualRequest("Find images with beach in their filenames") == false)
        #expect(VisualDescriptionRouting.isVisualRequest("Photos with names containing cat") == false)
        #expect(VisualDescriptionRouting.isVisualRequest("PDFs in Downloads from last week") == false)
    }

    @Test("All visual concepts must match and partial word matches do not count")
    func concepts() throws {
        let plan = try VisualDescriptionPlan(concepts: [["cat", "feline"], ["beach", "coast"]])
        let unrelated = VisualImageEvidence(labels: [.init(name: "vacation", confidence: 0.9), .init(name: "beach", confidence: 0.9)], text: "cat", textWasTruncated: false, thumbnail: Data())
        #expect(plan.matchingLabels(in: unrelated) == nil)
        let matching = VisualImageEvidence(labels: [.init(name: "cat", confidence: 0.9), .init(name: "coast", confidence: 0.9)], text: "", textWasTruncated: false, thumbnail: Data())
        #expect(plan.matchingLabels(in: matching) == ["cat", "coast"])
        #expect(throws: VisualDescriptionError.invalidInterpretation) { try VisualDescriptionPlan(concepts: [[]]) }
    }

    @MainActor @Test("Natural search uses image evidence, opt-out clears its query, manual search remains")
    func model() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Unrelated.jpg", "fixture")
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        model.setSource(fixture.source)
        model.naturalDraft = "Find photos taken by the sea"
        #expect(model.findPhotos() == nil)
        await model.analyze()?.value
        await model.findPhotos()?.value
        #expect(model.matches.count == 1)
        #expect(model.naturalPlan?.concepts.first?.contains("beach") == true)
        #expect(model.naturalRequest == "Find photos taken by the sea")
        model.setNaturalEnabled(false)
        await model.waitForSearch()
        #expect(model.naturalRequest == nil)
        #expect(model.naturalDraft.isEmpty)
        #expect(model.snapshot != nil)
        model.query = "invoice"
        await model.waitForSearch()
        #expect(model.matches.count == 1)
    }

    @MainActor @Test("Clear and opt-out reject a late photo interpretation", .timeLimit(.minutes(1)), arguments: [false, true])
    func lateInterpretation(_ optOut: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "fixture")
        let gate = FolderComparisonTestGate()
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()),
                                      interpreter: PausedVisualInterpreter(gate: gate))
        model.setSource(fixture.source)
        await model.analyze()?.value
        await model.waitForSearch()
        model.naturalDraft = "Find pictures of cats"
        let task = try #require(model.findPhotos())
        await gate.waitUntilEntered()
        if optOut { model.setNaturalEnabled(false) } else { model.clearIndex() }
        #expect(model.isWorking)
        #expect(model.findPhotos() == nil)
        await gate.release()
        await task.value
        await model.waitForSearch()
        #expect(model.isWorking == false)
        #expect(model.naturalPlan == nil)
        #expect(model.naturalRequest == nil)
        #expect(model.naturalDraft.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.matches.count == (optOut ? 1 : 0))
    }

    @MainActor @Test("An unsupported photo request preserves the previous evidence")
    func preservesEvidence() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Photo.jpg", "fixture")
        let model = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        model.setSource(fixture.source)
        await model.analyze()?.value
        model.naturalDraft = "Find photos by the sea"
        await model.findPhotos()?.value
        let request = model.naturalRequest
        let ids = model.matches.map(\.id)
        model.naturalDraft = "Find beach photos from yesterday"
        await model.findPhotos()?.value
        #expect(model.errorMessage != nil)
        #expect(model.naturalRequest == request)
        #expect(model.matches.map(\.id) == ids)
    }

    @Test("The actual on-device model resolves a non-shortcut photo description", .enabled(if: SystemLanguageModel.default.availability == .available), .timeLimit(.minutes(1)))
    func realModel() async throws {
        let plan = try await FoundationModelsVisualInterpreter().interpret("Find pictures depicting dogs on a beach")
        #expect(plan.concepts.count == 2)
        #expect(plan.concepts.contains { $0.contains("dog") || $0.contains("dogs") })
        #expect(plan.concepts.contains { $0.contains("beach") })
    }
}

nonisolated private struct PausedVisualInterpreter: VisualDescriptionInterpreting {
    let gate: FolderComparisonTestGate
    func interpret(_ description: String) async throws -> VisualDescriptionPlan {
        await gate.pause()
        return try VisualDescriptionPlan(concepts: [["cat"]])
    }
}
