import Foundation
import Testing
@testable import FinallyExplorer

struct FolderOrganizationTests {
    @Test("File-type organization proposes paths only and leaves nested folders untouched")
    func typesAndNoWrites() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        for name in ["Report.pdf", "Photo.png", "Code.json", "Data.csv", "Archive.zip", "Unknown.customextension"] {
            try fixture.write(name, "data")
        }
        try fixture.write("Project/Source.swift", "nested")
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.source.path).sorted()
        let plan = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType)
        let paths = Dictionary(uniqueKeysWithValues: plan.proposed.map { ($0.sourcePath, $0.destinationPath) })
        #expect(paths["Report.pdf"] == "Documents/Report.pdf")
        #expect(paths["Photo.png"] == "Images/Photo.png")
        #expect(paths["Code.json"] == "Code/Code.json")
        #expect(paths["Data.csv"] == "Spreadsheets/Data.csv")
        #expect(paths["Archive.zip"] == "Archives/Archive.zip")
        #expect(paths["Unknown.customextension"] == "Other/Unknown.customextension")
        #expect(plan.proposed.count == 6)
        #expect(plan.skipped.map(\.sourcePath) == ["Project"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.source.path).sorted() == before)
        #expect(try String(contentsOf: fixture.source.appending(path: "Project/Source.swift"), encoding: .utf8) == "nested")
    }

    @Test("Modification-month grouping uses the supplied calendar and never creates destinations")
    func dates() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.pdf", "data")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        let plan = try await FolderOrganizationService(calendar: calendar).preview(rootURL: fixture.source, rule: .modifiedMonth)
        #expect(plan.proposed.first?.destinationPath == "2026-09/Report.pdf")
        #expect(FileManager.default.fileExists(atPath: fixture.source.appending(path: "2026-09").path) == false)
    }

    @Test("Existing destinations, linked folders and hidden files cannot become silent moves")
    func collisionsAndHidden() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.pdf", "data")
        try fixture.write("Documents/Report.pdf", "keep")
        try fixture.write("Photo.png", "data")
        try fixture.write(".Secret.txt", "hidden")
        try FileManager.default.createSymbolicLink(at: fixture.source.appending(path: "Images"), withDestinationURL: fixture.destination)
        let plan = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType)
        #expect(plan.proposed.isEmpty)
        #expect(plan.excludedHiddenCount == 1)
        #expect(plan.skipped.first { $0.sourcePath == "Report.pdf" }?.skippedReason?.contains("already exists") == true)
        #expect(plan.skipped.first { $0.sourcePath == "Photo.png" }?.skippedReason != nil)
        #expect(try String(contentsOf: fixture.source.appending(path: "Documents/Report.pdf"), encoding: .utf8) == "keep")
        let hidden = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType, includesHidden: true)
        #expect(hidden.proposed.map(\.sourcePath) == [".Secret.txt"])
        #expect(try fixture.destinationNames().isEmpty)
    }

    @MainActor @Test("Changing the rule invalidates the previous preview")
    func modelReset() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.pdf", "data")
        let model = FolderOrganizationModel(rootURL: fixture.source)
        await model.preview()?.value
        #expect(model.plan?.proposed.count == 1)
        model.rule = .modifiedMonth
        #expect(model.plan == nil)
        await model.preview()?.value
        #expect(model.plan?.rule == .modifiedMonth)
        model.includesHidden = true
        #expect(model.plan == nil)
    }

    @MainActor @Test("Closing a preview rejects late completion", .timeLimit(.minutes(1)))
    func stalePreview() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let plan = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType)
        let gate = FolderComparisonTestGate()
        let model = FolderOrganizationModel(rootURL: fixture.source, planner: DelayedOrganizationPlanner(plan: plan, gate: gate))
        let task = try #require(model.preview())
        await gate.waitUntilEntered()
        model.cancel()
        await gate.release()
        await task.value
        #expect(model.plan == nil)
        #expect(model.isWorking == false)
        #expect(model.progress == nil)
    }
}

private nonisolated struct DelayedOrganizationPlanner: FolderOrganizationPlanning {
    let plan: FolderOrganizationPlan
    let gate: FolderComparisonTestGate
    func preview(rootURL: URL, rule: FolderOrganizationRule, includesHidden: Bool,
                 progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> FolderOrganizationPlan {
        await gate.pause()
        await progress(FolderWorkProgress(phase: "Late preview", relativePath: ""))
        return plan
    }
}
