import Darwin
import Foundation
import Testing
@testable import FinallyExplorer

struct FolderOrganizationApplyTests {
    @Test("Approved moves reuse folders and preserve bytes, identity, dates, mode and resource forks")
    func preservesFiles() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "report")
        try fixture.write("Documents/Existing.txt", "keep")
        try fixture.write("Photo.png", "image")
        try fixture.write("Zero.txt", "")
        try fixture.write("Project/Nested.swift", "nested")
        try fixture.write(".Secret.txt", "hidden")
        let value = Data("retained metadata".utf8)
        for key in ["com.finallyexplorer.test", XATTR_RESOURCEFORK_NAME] {
            #expect(value.withUnsafeBytes { setxattr(file.path, key, $0.baseAddress, $0.count, 0, 0) } == 0)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: date], ofItemAtPath: file.path)
        let plan = try await plan(fixture)
        let before = try #require(plan.snapshot.entries["Report.txt"]?.state)
        #expect(plan.foldersToCreate == ["Images"])
        let report = await FolderOrganizationApplyService().apply(plan)
        #expect(report.errorMessage == nil)
        #expect(report.wasCancelled == false)
        #expect(report.movedFiles.map(\.sourceName) == ["Photo.png", "Report.txt", "Zero.txt"])
        #expect(report.createdFolders == ["Images"])
        let target = fixture.source.appending(path: "Documents/Report.txt")
        #expect(try Data(contentsOf: target) == Data("report".utf8))
        let parent = try ScopedFolderDescriptor(rootURL: target.deletingLastPathComponent())
        let after = try #require(try parent.state(of: "Report.txt"))
        #expect(after.hasSameIdentity(as: before))
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect(attributes[.posixPermissions] as? Int == 0o640)
        #expect(attributes[.modificationDate] as? Date == date)
        for key in ["com.finallyexplorer.test", XATTR_RESOURCEFORK_NAME] {
            var data = Data(count: value.count)
            #expect(data.withUnsafeMutableBytes { getxattr(target.path, key, $0.baseAddress, $0.count, 0, 0) } == value.count)
            #expect(data == value)
        }
        #expect(try contents("Documents/Existing.txt", fixture) == "keep")
        #expect(try contents("Project/Nested.swift", fixture) == "nested")
        #expect(try contents(".Secret.txt", fixture) == "hidden")
        #expect(try contents("Documents/Zero.txt", fixture) == "")
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
        #expect(Set(report.changedDirectories.map(\.path)) == Set([fixture.source.path,
            fixture.source.appending(path: "Documents").path, fixture.source.appending(path: "Images").path]))
    }

    @Test("Month grouping applies the reviewed calendar result without recomputing it")
    func monthGrouping() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.pdf", "data")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        let snapshot = try await FolderOrganizationService(calendar: calendar).preview(rootURL: fixture.source, rule: .modifiedMonth)
        let report = await FolderOrganizationApplyService().apply(try FolderOrganizationMovePlan(snapshot: snapshot))
        #expect(report.errorMessage == nil)
        #expect(report.movedFiles.map(\.destinationPath) == ["2026-09/Report.pdf"])
        #expect(try contents("2026-09/Report.pdf", fixture) == "data")
    }

    @Test("A case alias of an existing category is reused when the filesystem supports it")
    func caseAlias() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("documents/Existing.txt", "keep")
        try fixture.write("Report.txt", "data")
        let isAlias = FileManager.default.fileExists(atPath: fixture.source.appending(path: "Documents").path)
        let plan = try await plan(fixture)
        #expect(plan.foldersToCreate == (isAlias ? [] : ["Documents"]))
        let report = await FolderOrganizationApplyService().apply(plan)
        #expect(report.errorMessage == nil)
        #expect(report.movedFiles.count == 1)
        #expect(try contents("documents/Existing.txt", fixture) == "keep")
        #expect(try contents("Documents/Report.txt", fixture) == "data")
    }

    @Test("Hidden files require opt-in and hard-linked files are never reorganized", arguments: [false, true])
    func exclusions(_ hidden: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let linked = try fixture.write("Linked.txt", "linked")
        try FileManager.default.linkItem(at: linked, to: fixture.source.appending(path: "Alias.txt"))
        try fixture.write("Visible.txt", "visible")
        try fixture.write(".Secret.txt", "secret")
        let snapshot = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType, includesHidden: hidden)
        #expect(snapshot.skipped.filter { $0.skippedReason?.contains("Hard-linked") == true }.count == 2)
        let report = await FolderOrganizationApplyService().apply(try FolderOrganizationMovePlan(snapshot: snapshot))
        #expect(report.errorMessage == nil)
        #expect(report.movedFiles.count == (hidden ? 2 : 1))
        #expect(try contents("Linked.txt", fixture) == "linked")
        #expect(try contents("Alias.txt", fixture) == "linked")
        #expect(try contents(hidden ? "Documents/.Secret.txt" : ".Secret.txt", fixture) == "secret")
    }

    @Test("Review rejects empty, duplicate, renamed, nested and escaping rows", arguments: ["empty", "duplicate", "rename", "nested", "escape", "absolute", "unknown"])
    func invalidPlans(_ kind: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Report.txt", "data")
        let snapshot = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType)
        let destination = switch kind {
        case "rename": "Documents/Renamed.txt"
        case "nested": "Documents/Nested/Report.txt"
        case "escape": "../Report.txt"
        case "absolute": "/Report.txt"
        default: "Documents/Report.txt"
        }
        let row = FolderOrganizationRow(sourcePath: kind == "unknown" ? "Missing.txt" : "Report.txt", destinationPath: destination, skippedReason: nil)
        let rows = kind == "empty" ? [] : kind == "duplicate" ? [row, row] : [row]
        let invalid = FolderOrganizationPlan(rootURL: snapshot.rootURL, rootState: snapshot.rootState, entries: snapshot.entries,
            destinationFolders: snapshot.destinationFolders, rule: snapshot.rule, proposed: rows, skipped: [], excludedHiddenCount: 0)
        #expect(throws: (any Error).self) { try FolderOrganizationMovePlan(snapshot: invalid) }
        #expect(try contents("Report.txt", fixture) == "data")
    }

    @Test("Hidden category folders cannot receive visible files without opt-in", arguments: [false, true])
    func hiddenDestination(_ includesHidden: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let folder = fixture.source.appending(path: "Documents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(chflags(folder.path, UInt32(UF_HIDDEN)) == 0)
        try fixture.write("Report.txt", "data")
        let snapshot = try await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType, includesHidden: includesHidden)
        #expect(snapshot.proposed.count == (includesHidden ? 1 : 0))
        if includesHidden {
            let report = await FolderOrganizationApplyService().apply(try FolderOrganizationMovePlan(snapshot: snapshot))
            #expect(report.errorMessage == nil)
            #expect(try contents("Documents/Report.txt", fixture) == "data")
        } else {
            #expect(snapshot.skipped.first { $0.sourcePath == "Report.txt" }?.skippedReason != nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }

    @Test("A filesystem refusal reports a created empty folder without deleting or copying the source")
    func renameRefusal() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = try fixture.write("Locked.txt", "keep")
        let target = fixture.source.appending(path: "Documents/Locked.txt")
        defer {
            _ = chflags(source.path, 0)
            _ = chflags(target.path, 0)
        }
        try #require(chflags(source.path, UInt32(UF_IMMUTABLE)) == 0)
        let report = await FolderOrganizationApplyService().apply(try await plan(fixture))
        #expect(report.errorMessage != nil)
        #expect(report.movedFiles.isEmpty)
        #expect(report.createdFolders == ["Documents"])
        #expect(report.changedDirectories.contains(fixture.source))
        #expect(try contents("Locked.txt", fixture) == "keep")
        #expect(FileManager.default.fileExists(atPath: target.path) == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).isEmpty)
    }

    @Test("All sources are checked before the first write", arguments: ["edit", "link", "hardlink", "missing"])
    func staleSource(_ change: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        let last = try fixture.write("Z.txt", "before")
        let approved = try await plan(fixture)
        switch change {
        case "edit": try Data("after!".utf8).write(to: last)
        case "hardlink": try FileManager.default.linkItem(at: last, to: fixture.destination.appending(path: "Alias.txt"))
        default:
            try FileManager.default.removeItem(at: last)
            if change == "link" {
                let outside = try fixture.write("Outside.txt", "outside", in: fixture.destination)
                try FileManager.default.createSymbolicLink(at: last, withDestinationURL: outside)
            }
        }
        let report = await FolderOrganizationApplyService().apply(approved)
        #expect(report.errorMessage != nil)
        #expect(report.movedFiles.isEmpty)
        #expect(report.createdFolders.isEmpty)
        #expect(report.changedDirectories.isEmpty)
        #expect(try contents("A.txt", fixture) == "first")
        #expect(FileManager.default.fileExists(atPath: fixture.source.appending(path: "Documents").path) == false)
    }

    @Test("Destinations changed after preview block every write", arguments: ["collision", "newFolder", "folderLink", "folderReplacement", "rootReplacement"])
    func staleDestination(_ change: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("Z.txt", "last")
        let folder = fixture.source.appending(path: "Documents")
        if change != "newFolder" { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let approved = try await plan(fixture)
        switch change {
        case "collision": try fixture.write("Documents/Z.txt", "keep")
        case "newFolder": try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        case "rootReplacement":
            try FileManager.default.moveItem(at: fixture.source, to: fixture.root.appending(path: "Original"))
            try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
        default:
            try FileManager.default.moveItem(at: folder, to: fixture.root.appending(path: "Original"))
            if change == "folderLink" { try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: fixture.destination) }
            else { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        }
        let report = await FolderOrganizationApplyService().apply(approved)
        #expect(report.errorMessage != nil)
        #expect(report.movedFiles.isEmpty)
        #expect(report.createdFolders.isEmpty)
        #expect(try fixture.destinationNames().isEmpty)
        if change == "collision" { #expect(try contents("Documents/Z.txt", fixture) == "keep") }
        if change == "rootReplacement" {
            #expect(try String(contentsOf: fixture.root.appending(path: "Original/A.txt"), encoding: .utf8) == "first")
        } else { #expect(try contents("A.txt", fixture) == "first") }
    }

    @Test("Late collisions and parent replacement retain completed moves and never overwrite", arguments: ["collision", "parentLink", "sourceEdit", "rootReplacement"])
    func partialFailure(_ change: String) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("Z.txt", "last")
        let report = await FolderOrganizationApplyService().apply(try await plan(fixture)) { progress in
            guard progress.phase == "Moving approved files…", progress.completedItems == 1 else { return }
            do {
                switch change {
                case "collision": try fixture.write("Documents/Z.txt", "keep")
                case "sourceEdit": try fixture.write("Z.txt", "edit")
                case "rootReplacement":
                    try FileManager.default.moveItem(at: fixture.source, to: fixture.root.appending(path: "Original"))
                    try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
                default:
                    let folder = fixture.source.appending(path: "Documents")
                    try FileManager.default.moveItem(at: folder, to: fixture.root.appending(path: "Original"))
                    try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: fixture.destination)
                }
            } catch { Issue.record(error) }
        }
        #expect(report.errorMessage != nil)
        #expect(report.movedFiles.map(\.sourceName) == ["A.txt"])
        #expect(report.createdFolders == ["Documents"])
        #expect(try fixture.destinationNames().isEmpty)
        if change == "rootReplacement" {
            #expect(try String(contentsOf: fixture.root.appending(path: "Original/Z.txt"), encoding: .utf8) == "last")
        } else { #expect(try contents("Z.txt", fixture) == (change == "sourceEdit" ? "edit" : "last")) }
        if change == "collision" { #expect(try contents("Documents/Z.txt", fixture) == "keep") }
    }

    @Test("Cancellation stops at the next safe boundary and reports only completed moves", .timeLimit(.minutes(1)), arguments: [0, 1])
    func cancellation(_ completed: Int) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("Z.txt", "last")
        let approved = try await plan(fixture)
        let gate = FolderComparisonTestGate()
        let task = Task {
            await FolderOrganizationApplyService().apply(approved) { progress in
                if progress.phase == "Moving approved files…", progress.completedItems == completed { await gate.pause() }
            }
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        let report = await task.value
        #expect(report.wasCancelled)
        #expect(report.errorMessage == nil)
        #expect(report.movedFiles.count == completed)
        #expect(report.createdFolders == (completed == 0 ? [] : ["Documents"]))
        #expect(try contents("Z.txt", fixture) == "last")
        #expect(try contents(completed == 0 ? "A.txt" : "Documents/A.txt", fixture) == "first")
    }

    private func plan(_ fixture: FolderComparisonTestFixture) async throws -> FolderOrganizationMovePlan {
        try FolderOrganizationMovePlan(snapshot: await FolderOrganizationService().preview(rootURL: fixture.source, rule: .fileType))
    }

    private func contents(_ path: String, _ fixture: FolderComparisonTestFixture) throws -> String {
        try String(contentsOf: fixture.source.appending(path: path), encoding: .utf8)
    }
}
