import AppKit
import SwiftUI
import Testing
@testable import FinallyExplorer

@MainActor
struct FileToolsPresentationTests {
    @Test("Tools launcher and disabled actions render in every palette", arguments: ExplorerThemeChoice.allCases, [false, true])
    func toolsPresentation(_ choice: ExplorerThemeChoice, _ dark: Bool) throws {
        try render(ExplorerToolsPopover(hasFolder: true, onSelect: { _ in }, onClose: {}),
                   name: "Tools-\(choice.rawValue)", width: 430, height: 540, dark: dark, choice: choice)
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let model = VisualSearchModel()
        model.setSource(fixture.source)
        try render(VisualSearchSheet(model: model, onReveal: { _ in }), name: "VisualControls-\(choice.rawValue)",
                   width: 820, height: 720, dark: dark, choice: choice)
        #expect(model.snapshot == nil && model.progress == nil, "Presenting the controls must not start analysis")
    }

    @Test("Ask AI introduction keeps actions and explanations visible", arguments: [false, true])
    func askAILayout(_ dark: Bool) throws {
        let suite = "FinallyExplorer.AskAI.Layout.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AskAISearchModel()
        try render(AskAISearchSheet(model: model, settings: ExplorerAISettings(defaults: defaults),
            rootURL: URL(filePath: "/tmp"), onReveal: { _ in }), name: "AskAIIntroduction", width: 700, height: 600, dark: dark)
        #expect(model.turns.isEmpty && model.pendingRequest == nil)
    }

    @Test("OCR summaries and source warnings fit with five documents in both themes", arguments: [false, true])
    func scannedDocumentLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let scan = fixture.source.appending(path: "Scanned Quarterly Invoice Report.pdf")
        try DocumentQuestionFixtures.pdf(pages: [""]).write(to: scan)
        var urls = [scan]
        for index in 1...4 { urls.append(try fixture.write("Additional Document \(index).txt", "A supporting cover sheet.")) }
        let model = DocumentQuestionModel(
            reader: LocalDocumentReader(textRecognizer: RecordingDocumentTextRecognizer()),
            answerer: QuotingDocumentAnswerer(),
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select(urls)
        await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        #expect(model.documents.count == 5)
        let claim = try #require(model.claims.first)
        #expect(claim.source.isOCR)
        try render(DocumentQuestionSheet(model: model, onReveal: { _ in }), name: "ScannedDocumentAnswer", width: 820, height: 720, dark: dark)
        try render(DocumentCitationSheet(claim: claim, onReveal: {}), name: "ScannedDocumentCitation", width: 600, height: 380, dark: dark)
    }

    @Test("Document questions, source excerpts, and AI settings fit in both themes", arguments: [false, true])
    func documentLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        var urls: [URL] = []
        for index in 1...5 { urls.append(try fixture.write("Quarterly Invoice Report \(index).txt", "The payment deadline is 30 September 2026.")) }
        let model = DocumentQuestionModel(answerer: QuotingDocumentAnswerer(),
            resolver: RecordingDocumentResolver(result: "What is the payment deadline?"),
            search: LocalDocumentPassageSearch(encoder: UnavailableDocumentSemanticEncoder()))
        model.select(urls)
        await model.readDocuments()?.value
        model.question = "What is the payment deadline?"
        await model.ask()?.value
        model.question = "When is it due?"
        await model.ask()?.value
        #expect(model.history.count == 2)
        let claim = try #require(model.claims.first)
        try render(DocumentQuestionSheet(model: model, onReveal: { _ in }), name: "DocumentAnswer", width: 820, height: 720, dark: dark)
        try render(DocumentCitationSheet(claim: claim, onReveal: {}), name: "DocumentCitation", width: 600, height: 380, dark: dark)
        let suite = "FinallyExplorer.AISettings.Layout.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try render(ExplorerAISettingsView(settings: ExplorerAISettings(defaults: defaults)), name: "ExpandedAISettings", width: 580, height: 720, dark: dark)
    }

    @Test("Visual search empty and analyzed states fit in light and dark", arguments: [false, true])
    func visualSearchLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let image = fixture.source.appending(path: "Receipt.png")
        try VisualSearchTestFixtures.receiptImage().write(to: image)
        let empty = VisualSearchModel()
        empty.setSource(fixture.source)
        try render(VisualSearchSheet(model: empty, onReveal: { _ in }), name: "VisualSearchEmpty", width: 820, height: 720, dark: dark)
        let populated = VisualSearchModel(service: VisualSearchService(analyzer: PresentationVisualAnalyzer()))
        populated.setSource(fixture.source)
        await populated.analyze()?.value
        populated.query = "invoice"
        await populated.waitForSearch()
        #expect(populated.matches.count == 1)
        try render(VisualSearchSheet(model: populated, onReveal: { _ in }), name: "VisualSearchResults", width: 820, height: 720, dark: dark)
        let natural = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        natural.setSource(fixture.source)
        await natural.analyze()?.value
        natural.naturalDraft = "Find photos taken by the sea"
        await natural.findPhotos()?.value
        #expect(natural.matches.count == 1)
        try render(VisualSearchSheet(model: natural, onReveal: { _ in }), name: "NaturalVisualSearch", width: 820, height: 720, dark: dark)
        // Closing a rendered sheet ends its lifecycle. Use a separate owner for
        // subsequent work so its deferred onDisappear cannot cancel that work.
        let filtered = VisualSearchModel(service: VisualSearchService(analyzer: FixedVisualAnalyzer()))
        filtered.setSource(fixture.source)
        await filtered.analyze()?.value
        filtered.naturalDraft = "Find beach photos from last week"
        await filtered.findPhotos()?.value
        filtered.naturalDraft = "Only HEIC"
        await filtered.findPhotos()?.value
        #expect(filtered.errorMessage == nil)
        #expect(filtered.naturalPlan?.filters.captureInterval != nil)
        #expect(filtered.naturalPlan?.filters.fileExtensions == ["heic"])
        try render(VisualSearchSheet(model: filtered, onReveal: { _ in }), name: "FilteredVisualSearch", width: 820, height: 720, dark: dark)
    }

    @Test("Offline catalogs fit in light and dark without accessing a live disk", arguments: [false, true])
    func offlineCatalogLayout(_ dark: Bool) async throws {
        let fixture = try OfflineCatalogTestFixture()
        defer { fixture.remove() }
        try fixture.files.write("Reports/Accounting invoice.pdf", "metadata fixture")
        try fixture.files.write("Design/Reference.png", "fixture")
        let saved = try await fixture.store.save(fixture.scan())
        let model = OfflineCatalogModel(store: fixture.store, volumes: LocalOfflineVolumeAccess(fixtureVolumes: []))
        await model.load()?.value
        await model.waitForSearch()
        let monitor = MountedVolumeMonitor(loadVolumes: { [] }, observesWorkspaceChanges: false)
        try render(OfflineCatalogSheet(model: model, mountedVolumes: monitor, onReveal: { _, _ in }), name: "OfflineCatalog", width: 820, height: 720, dark: dark)
        try render(OfflineCatalogRemovalSheet(summary: saved, onConfirm: {}), name: "OfflineRemoval", width: 500, height: 240, dark: dark)
        let prepared = OfflineCatalogModel(store: fixture.store, volumes: fixture.access)
        await prepared.load()?.value
        await prepared.prepare(fixture.files.source)?.value
        await prepared.waitForSearch()
        try render(OfflineCatalogSheet(model: prepared, mountedVolumes: monitor, onReveal: { _, _ in }), name: "OfflinePrepared", width: 820, height: 720, dark: dark)
    }

    @Test("Duplicate and organization previews, reviews and completion fit in light and dark", arguments: [false, true])
    func offscreenLayout(_ dark: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Reports/Accounting report.pdf", "same")
        try fixture.write("Archived accounting report.pdf", "same")
        try fixture.write("Source.json", "source")
        let duplicates = DuplicateFilesModel(rootURL: fixture.source, operations: FileOperationCoordinator())
        await duplicates.scan()?.value
        let snapshot = try #require(duplicates.snapshot)
        let plan = try DuplicateTrashPlan(snapshot: snapshot, selection: ["Archived accounting report.pdf"])
        try render(DuplicateFilesSheet(model: duplicates, onReveal: { _ in }), name: "Duplicates", width: 760, height: 660, dark: dark)
        try render(DuplicateTrashReviewSheet(plan: plan, onConfirm: {}), name: "DuplicateReview", width: 620, height: 540, dark: dark)
        let operations = FileOperationCoordinator()
        let organization = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        await organization.preview()?.value
        try render(FolderOrganizationSheet(model: organization), name: "Organization", width: 760, height: 660, dark: dark)
        organization.reviewMoves()
        let moves = try #require(organization.review)
        try render(FolderOrganizationReviewSheet(plan: moves, onConfirm: {}), name: "OrganizationReview", width: 620, height: 560, dark: dark)
        // A rendered sheet is torn down when its offscreen window closes and
        // legitimately calls cancel(). Do not reuse that lifecycle owner for work.
        let completion = FolderOrganizationModel(rootURL: fixture.source, operations: operations)
        await completion.preview()?.value
        completion.reviewMoves()
        let approved = try #require(completion.review)
        #expect(completion.confirmMoves(approved))
        await operations.waitForCurrentOperation()
        #expect(completion.report?.movedFiles.count == approved.moves.count)
        #expect(completion.report?.errorMessage == nil)
        #expect(completion.report?.wasCancelled == false)
        try render(FolderOrganizationSheet(model: completion), name: "OrganizationReport", width: 760, height: 660, dark: dark)
    }

    private func render(_ view: some View, name: String, width: CGFloat, height: CGFloat, dark: Bool, choice: ExplorerThemeChoice = .mesa) throws {
        let view = view.environment(\.explorerTheme, ExplorerTheme.palette(for: choice))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width <= width)
        #expect(hosting.fittingSize.height <= height)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1_000)
        try png.write(to: URL.temporaryDirectory.appending(path: "FinallyExplorer-\(name)-\(dark ? "dark" : "light").png"), options: .atomic)
    }
}

private nonisolated struct PresentationVisualAnalyzer: VisualImageAnalyzing {
    func analyze(_ data: Data) async throws -> VisualImageEvidence {
        VisualImageEvidence(labels: [.init(name: "document", confidence: 0.9)],
            text: "INVOICE 4827", textWasTruncated: false, thumbnail: data)
    }
}
