import Darwin
import Foundation
import Testing
@testable import FinallyExplorer

struct VerifiedCopyServiceTests {
    @Test("Verified copy adds missing files and empty folders without changing existing data")
    func copiesMissingOnly() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Nested/Report.txt", "report")
        try fixture.write("Existing.txt", "new")
        try fixture.write("Existing.txt", "keep", in: fixture.destination)
        try FileManager.default.createDirectory(at: fixture.source.appending(path: "Empty"), withIntermediateDirectories: true)
        let report = await VerifiedCopyService().copy(try await fixture.plan())
        #expect(report.errorMessage == nil)
        #expect(report.wasCancelled == false)
        #expect(report.verifiedFiles == ["Nested/Report.txt"])
        #expect(report.createdDirectories == ["Empty", "Nested"])
        #expect(try String(contentsOf: fixture.destination.appending(path: "Nested/Report.txt"), encoding: .utf8) == "report")
        #expect(try String(contentsOf: fixture.destination.appending(path: "Existing.txt"), encoding: .utf8) == "keep")
        #expect(Set(report.changedDirectories.map(\.path)) == [fixture.destination.path, fixture.destination.appending(path: "Nested").path])
        #expect(try fixture.destinationNames() == ["Empty", "Existing.txt", "Nested"])
    }

    @Test("Multi-chunk data and zero-byte files verify successfully; file metadata is retained")
    func dataAndMetadata() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = fixture.source.appending(path: "Large.bin")
        let data = Data(repeating: 0xa5, count: 2_100_000)
        try data.write(to: source)
        let attribute = Data("retained attribute".utf8)
        let xattrResult = attribute.withUnsafeBytes {
            setxattr(source.path, "com.finallyexplorer.test", $0.baseAddress, $0.count, 0, 0)
        }
        #expect(xattrResult == 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: source.path)
        try fixture.write("Zero.txt", "")
        let report = await VerifiedCopyService().copy(try await fixture.plan())
        #expect(report.errorMessage == nil)
        #expect(report.verifiedFiles == ["Large.bin", "Zero.txt"])
        let copied = fixture.destination.appending(path: "Large.bin")
        #expect(try Data(contentsOf: copied) == data)
        let attributes = try FileManager.default.attributesOfItem(atPath: copied.path)
        #expect(attributes[.posixPermissions] as? Int == 0o640)
        #expect(attributes[.modificationDate] as? Date == Date(timeIntervalSince1970: 1_700_000_000))
        var retained = Data(count: attribute.count)
        let count = retained.withUnsafeMutableBytes {
            getxattr(copied.path, "com.finallyexplorer.test", $0.baseAddress, $0.count, 0, 0)
        }
        #expect(count == attribute.count)
        #expect(retained == attribute)
    }

    @Test("Preflight rejects changes to any approved source before writing even the first item")
    func changedSource() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        let source = try fixture.write("Z.txt", "before")
        let plan = try await fixture.plan()
        try Data("after!".utf8).write(to: source)
        let report = await VerifiedCopyService().copy(plan)
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try fixture.destinationNames().isEmpty)
    }

    @Test("Preflight never replaces a destination created after the comparison")
    func destinationCollision() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("Z.txt", "source")
        let plan = try await fixture.plan()
        let existing = try fixture.write("Z.txt", "keep", in: fixture.destination)
        let report = await VerifiedCopyService().copy(plan)
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try fixture.destinationNames() == ["Z.txt"])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
    }

    @Test("Replacing either parent with a symlink cannot redirect a copy", arguments: [false, true])
    func replacedParent(_ replaceSource: Bool) async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Nested/File.txt", "data")
        try FileManager.default.createDirectory(at: fixture.destination.appending(path: "Nested"), withIntermediateDirectories: true)
        let outside = fixture.root.appending(path: "Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let plan = try await fixture.plan()
        let parent = (replaceSource ? fixture.source : fixture.destination).appending(path: "Nested")
        try FileManager.default.moveItem(at: parent, to: fixture.root.appending(path: "Original"))
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
        let report = await VerifiedCopyService().copy(plan)
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("A parent moved during verification cannot receive the published file")
    func lateParentRelocation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Nested/File.txt", "source")
        let parent = fixture.destination.appending(path: "Nested")
        let relocated = fixture.root.appending(path: "Relocated")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                do {
                    try FileManager.default.moveItem(at: parent, to: relocated)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                } catch { Issue.record(error) }
            }
        }
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: relocated.path).isEmpty)
    }

    @Test("A root moved during verification does not receive a published copy")
    func lateRootRelocation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "source")
        let relocated = fixture.root.appending(path: "Relocated")
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                do { try FileManager.default.moveItem(at: fixture.destination, to: relocated) }
                catch { Issue.record(error) }
            }
        }
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: relocated.path).isEmpty)
    }

    @Test("Corrupted staged data is never published and staging is cleaned up")
    func corruptedStaging() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "correct")
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                do {
                    let staging = try #require(fixture.destinationNames().first { $0.hasPrefix(".finally-verified-") })
                    try Data("corrupt".utf8).write(to: fixture.destination.appending(path: staging))
                } catch { Issue.record(error) }
            }
        }
        #expect(report.errorMessage == FolderComparisonError.verificationFailed("File.txt").localizedDescription)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try fixture.destinationNames().isEmpty)
    }

    @Test("A collision after preflight cannot overwrite or rename the existing file")
    func lateCollision() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "source")
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                do { try fixture.write("File.txt", "late arrival", in: fixture.destination) }
                catch { Issue.record(error) }
            }
        }
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try fixture.destinationNames() == ["File.txt"])
        #expect(try String(contentsOf: fixture.destination.appending(path: "File.txt"), encoding: .utf8) == "late arrival")
    }

    @Test("Source mutation during copying cannot publish stale data")
    func lateSourceChange() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let source = try fixture.write("File.txt", "before")
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                do { try Data("after!".utf8).write(to: source) }
                catch { Issue.record(error) }
            }
        }
        #expect(report.errorMessage != nil)
        #expect(report.verifiedFiles.isEmpty)
        #expect(try fixture.destinationNames().isEmpty)
    }

    @Test("A cleanup permission failure explicitly identifies the remaining temporary file")
    func cleanupFailureIsReported() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer {
            _ = chflags(fixture.destination.path, 0)
            fixture.remove()
        }
        try fixture.write("File.txt", "data")
        let report = await VerifiedCopyService().copy(try await fixture.plan()) { progress in
            if progress.phase == "Verifying copied data…" {
                #expect(chflags(fixture.destination.path, UInt32(UF_IMMUTABLE)) == 0)
            }
        }
        #expect(report.verifiedFiles.isEmpty)
        #expect(report.errorMessage?.contains("temporary file could not be removed") == true)
        let remaining = try fixture.destinationNames()
        #expect(remaining.count == 1)
        #expect(remaining.first?.hasPrefix(".finally-verified-") == true)
        #expect(report.errorMessage?.contains(try #require(remaining.first)) == true)
    }

    @Test("Cancellation preserves only completed verified copies and removes unpublished staging")
    func partialCancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "first")
        try fixture.write("B.txt", "second")
        let plan = try await fixture.plan()
        let task = Task {
            await VerifiedCopyService().copy(plan) { progress in
                if progress.relativePath == "B.txt" {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        let report = await task.value
        #expect(report.wasCancelled)
        #expect(report.errorMessage == nil)
        #expect(report.verifiedFiles == ["A.txt"])
        #expect(try fixture.destinationNames() == ["A.txt"])
        #expect(report.changedDirectories == [fixture.destination])
    }

    @Test("Cancellation before work never creates items")
    func initiallyCancelled() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("File.txt", "data")
        let plan = try await fixture.plan()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await VerifiedCopyService().copy(plan)
        }
        let report = await task.value
        #expect(report.wasCancelled)
        #expect(try fixture.destinationNames().isEmpty)
    }
}
