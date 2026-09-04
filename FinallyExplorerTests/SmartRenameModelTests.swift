//
//  SmartRenameModelTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct SmartRenameModelTests {
    private let request = SmartRenameRequest(
        itemURL: URL(filePath: "/tmp/Quarterly Report.pdf"),
        isDirectory: false
    )

    @Test("A generated suggestion replaces loading state without touching the filesystem")
    func successfulSuggestionUpdatesState() async {
        let expectedSuggestion = SmartRenameSuggestion(
            originalName: "Quarterly Report.pdf",
            suggestedName: "Q3 Financial Report.pdf",
            contentWasUsed: false
        )
        let service = SmartRenameServiceFake(
            response: expectedSuggestion
        )
        let model = SmartRenameModel(service: service)

        model.generateSuggestion(for: request)

        #expect(model.isLoading)
        #expect(model.suggestion == nil)
        #expect(model.errorMessage == nil)

        await model.awaitCurrentGenerationForTesting()

        #expect(model.isLoading == false)
        #expect(model.suggestion == expectedSuggestion)
        #expect(model.errorMessage == nil)
        #expect(await service.requests() == [request])
    }

    @Test("A service failure becomes a user-facing error without a stale suggestion")
    func serviceFailureUpdatesErrorState() async {
        let service = SmartRenameServiceFake(error: .failed)
        let model = SmartRenameModel(service: service)

        model.generateSuggestion(for: request)
        await model.awaitCurrentGenerationForTesting()

        #expect(model.isLoading == false)
        #expect(model.suggestion == nil)
        #expect(model.errorMessage == "Smart Rename failed for testing.")
    }

    @Test("A superseded generation cannot replace the latest suggestion")
    func staleGenerationIsDiscarded() async {
        let service = ControlledSmartRenameService()
        let model = SmartRenameModel(service: service)
        let oldRequest = SmartRenameRequest(
            itemURL: URL(filePath: "/tmp/Old.txt"),
            isDirectory: false
        )
        let newRequest = SmartRenameRequest(
            itemURL: URL(filePath: "/tmp/New.txt"),
            isDirectory: false
        )

        let oldTask = model.generateSuggestion(for: oldRequest)
        await service.waitUntilRequested("Old.txt")

        let newTask = model.generateSuggestion(for: newRequest)
        await service.waitUntilRequested("New.txt")

        let newSuggestion = SmartRenameSuggestion(
            originalName: "New.txt",
            suggestedName: "Current.txt",
            contentWasUsed: false
        )
        await service.resolve("New.txt", with: newSuggestion)
        await newTask.value

        let oldSuggestion = SmartRenameSuggestion(
            originalName: "Old.txt",
            suggestedName: "Stale.txt",
            contentWasUsed: false
        )
        await service.resolve("Old.txt", with: oldSuggestion)
        await oldTask.value

        #expect(model.suggestion == newSuggestion)
        #expect(model.errorMessage == nil)
        #expect(model.isLoading == false)
    }

    @Test("Cancellation clears loading without presenting an error")
    func cancellationIsSilent() async {
        let service = ControlledSmartRenameService()
        let model = SmartRenameModel(service: service)

        let task = model.generateSuggestion(for: request)
        await service.waitUntilRequested(request.itemURL.lastPathComponent)
        model.cancelSuggestion()
        await service.resolve(
            request.itemURL.lastPathComponent,
            with: SmartRenameSuggestion(
                originalName: request.itemURL.lastPathComponent,
                suggestedName: "Ignored.pdf",
                contentWasUsed: false
            )
        )
        await task.value

        #expect(model.isLoading == false)
        #expect(model.suggestion == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("Availability is forwarded by the injected service")
    func availabilityIsForwarded() async {
        let service = SmartRenameServiceFake(
            availability: .appleIntelligenceNotEnabled,
            response: SmartRenameSuggestion(
                originalName: "Unused.txt",
                suggestedName: "Unused.txt",
                contentWasUsed: false
            )
        )
        let model = SmartRenameModel(service: service)

        #expect(
            await model.availability() == .appleIntelligenceNotEnabled
        )
    }
}

struct SmartRenameNameComposerTests {
    @Test("A file keeps its original extension and capitalization")
    func preservesOriginalExtension() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Quarterly Summary",
            originalURL: URL(filePath: "/tmp/report.PDF"),
            preservesExtension: true
        )

        #expect(result == "Quarterly Summary.PDF")
    }

    @Test("An accidentally repeated extension is removed before preservation")
    func avoidsDuplicateExtension() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Quarterly Summary.pdf",
            originalURL: URL(filePath: "/tmp/report.PDF"),
            preservesExtension: true
        )

        #expect(result == "Quarterly Summary.PDF")
    }

    @Test("Directory dots are names, not extensions")
    func leavesDirectoryNameIntact() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Archive.2026",
            originalURL: URL(
                filePath: "/tmp/Old.Archive",
                directoryHint: .isDirectory
            ),
            preservesExtension: false
        )

        #expect(result == "Archive.2026")
    }

    @Test("The final composed name is checked by the shared rename validator")
    func rejectsInvalidFinalName() {
        #expect(
            throws: FileRenameNameValidator.ValidationError.containsPathSeparator
        ) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Unsafe/Name",
                originalURL: URL(filePath: "/tmp/report.pdf"),
                preservesExtension: true
            )
        }
    }

    @Test("A package directory keeps the suffix that makes it launchable")
    func preservesApplicationPackageExtension() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Photo Editor",
            originalURL: URL(
                filePath: "/Applications/Old Name.app",
                directoryHint: .isDirectory
            ),
            preservesExtension: false
        )

        #expect(result == "Photo Editor.app")
    }

    @Test("A compound archive extension is preserved as one suffix")
    func preservesCompoundExtension() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Project Backup.tar.gz",
            originalURL: URL(filePath: "/tmp/archive.TAR.GZ"),
            preservesExtension: true
        )

        #expect(result == "Project Backup.TAR.GZ")
    }

    @Test("A generated name cannot unexpectedly hide a visible item")
    func rejectsNewLeadingDot() {
        #expect(throws: SmartRenameOutputError.wouldHideVisibleItem) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: ".Secret Report",
                originalURL: URL(filePath: "/tmp/report.pdf"),
                preservesExtension: true
            )
        }
    }

    @Test("A hidden item stays hidden without trusting the model to preserve its dot")
    func preservesHiddenState() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Environment Settings",
            originalURL: URL(filePath: "/tmp/.env"),
            preservesExtension: false
        )

        #expect(result == ".Environment Settings")
    }

    @Test("Control characters from generated output are rejected")
    func rejectsControlCharacters() {
        #expect(throws: SmartRenameOutputError.containsControlCharacters) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Quarterly\nReport",
                originalURL: URL(filePath: "/tmp/report.pdf"),
                preservesExtension: true
            )
        }
    }

    @Test("Illegal Unicode scalars from generated output are rejected")
    func rejectsIllegalUnicodeScalars() {
        #expect(throws: SmartRenameOutputError.containsIllegalCharacters) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Quarterly\u{FFFF}Report",
                originalURL: URL(filePath: "/tmp/report.pdf"),
                preservesExtension: true
            )
        }
    }

    @Test("Unicode line separators from generated output are rejected")
    func rejectsUnicodeLineSeparators() {
        #expect(throws: SmartRenameOutputError.containsLineSeparators) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Quarterly\u{2028}Report",
                originalURL: URL(filePath: "/tmp/report.pdf"),
                preservesExtension: true
            )
        }
    }

    @Test("An extensionless file cannot gain a model-invented extension")
    func preservesExtensionlessFileType() {
        #expect(throws: SmartRenameOutputError.wouldAddFileExtension) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Invoice.pdf",
                originalURL: URL(filePath: "/tmp/Invoice"),
                preservesExtension: true
            )
        }
    }

    @Test("An ordinary folder cannot become an app package")
    func ordinaryFolderCannotBecomePackage() {
        #expect(throws: SmartRenameOutputError.wouldCreatePackage) {
            try SmartRenameNameComposer.validatedName(
                proposedBaseName: "Photo Editor.app",
                originalURL: URL(
                    filePath: "/tmp/Photos",
                    directoryHint: .isDirectory
                ),
                preservesExtension: false
            )
        }
    }

    @Test("Dots remain valid in an ordinary folder name")
    func ordinaryFolderMayContainDots() throws {
        let result = try SmartRenameNameComposer.validatedName(
            proposedBaseName: "Archive.2026",
            originalURL: URL(
                filePath: "/tmp/Archive",
                directoryHint: .isDirectory
            ),
            preservesExtension: false
        )

        #expect(result == "Archive.2026")
    }
}

struct SmartRenameContentExtractorTests {
    @Test("Text extraction reads only a bounded local prefix")
    func textSnippetIsBounded() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "notes.swift")
        try Data("abcdefghijklmnop".utf8).write(to: fileURL)
        let extractor = LocalSmartRenameContentExtractor(
            limits: SmartRenameContentLimits(
                maximumCharacterCount: 8,
                maximumTextByteCount: 32,
                maximumPDFPageCount: 1
            )
        )

        let snippet = try await extractor.snippet(for: fileURL)

        #expect(snippet == "abcdefgh")
    }

    @Test("Content extraction ignores non-regular filesystem items")
    func ignoresNonRegularItems() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString).txt",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let extractor = LocalSmartRenameContentExtractor()

        #expect(try await extractor.snippet(for: directory) == nil)
    }
}

struct SmartRenameItemEligibilityTests {
    @Test("Smart Rename is exposed only for verified regular files")
    func onlyVerifiedRegularFilesAreEligible() {
        #expect(
            SmartRenameItemEligibility.isEligible(
                isNewFolder: false,
                isRegularFile: true,
                isSymbolicLink: false
            )
        )
        #expect(
            SmartRenameItemEligibility.isEligible(
                isNewFolder: true,
                isRegularFile: true,
                isSymbolicLink: false
            ) == false
        )
        #expect(
            SmartRenameItemEligibility.isEligible(
                isNewFolder: false,
                isRegularFile: false,
                isSymbolicLink: false
            ) == false
        )
        #expect(
            SmartRenameItemEligibility.isEligible(
                isNewFolder: false,
                isRegularFile: true,
                isSymbolicLink: true
            ) == false
        )
    }
}

private actor SmartRenameServiceFake: SmartRenameServicing {
    private let availabilityValue: SmartRenameAvailability
    private let response: SmartRenameSuggestion?
    private let error: SmartRenameTestError?
    private var recordedRequests: [SmartRenameRequest] = []

    init(
        availability: SmartRenameAvailability = .available,
        response: SmartRenameSuggestion? = nil,
        error: SmartRenameTestError? = nil
    ) {
        availabilityValue = availability
        self.response = response
        self.error = error
    }

    func availability() async -> SmartRenameAvailability {
        availabilityValue
    }

    func suggestName(for request: SmartRenameRequest) async throws
        -> SmartRenameSuggestion {
        recordedRequests.append(request)
        if let error { throw error }
        return response ?? SmartRenameSuggestion(
            originalName: request.itemURL.lastPathComponent,
            suggestedName: request.itemURL.lastPathComponent,
            contentWasUsed: false
        )
    }

    func requests() -> [SmartRenameRequest] {
        recordedRequests
    }
}

private actor ControlledSmartRenameService: SmartRenameServicing {
    private var continuations: [
        String: CheckedContinuation<SmartRenameSuggestion, any Error>
    ] = [:]

    func availability() async -> SmartRenameAvailability {
        .available
    }

    func suggestName(for request: SmartRenameRequest) async throws
        -> SmartRenameSuggestion {
        try await withCheckedThrowingContinuation { continuation in
            continuations[request.itemURL.lastPathComponent] = continuation
        }
    }

    func waitUntilRequested(_ name: String) async {
        while continuations[name] == nil {
            await Task.yield()
        }
    }

    func resolve(
        _ name: String,
        with suggestion: SmartRenameSuggestion
    ) {
        continuations.removeValue(forKey: name)?.resume(
            returning: suggestion
        )
    }
}

private nonisolated enum SmartRenameTestError: LocalizedError, Sendable {
    case failed

    var errorDescription: String? {
        "Smart Rename failed for testing."
    }
}
