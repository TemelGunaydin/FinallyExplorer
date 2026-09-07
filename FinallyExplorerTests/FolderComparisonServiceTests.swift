import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FinallyExplorer

struct FolderComparisonServiceTests {
    @Test("Comparison hashes data, not names, size or modification date alone")
    func dataComparison() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Same.txt", "abc")
        let same = try fixture.write("Same.txt", "abc", in: fixture.destination)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: same.path)
        try fixture.write("Different.txt", "abc")
        try fixture.write("Different.txt", "xyz", in: fixture.destination)
        try fixture.write("Nested/Only source.txt", "source")
        try fixture.write("Only destination.txt", "destination", in: fixture.destination)
        try FileManager.default.createDirectory(at: fixture.source.appending(path: "Empty"), withIntermediateDirectories: true)

        let snapshot = try await fixture.compare()
        let statuses = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.relativePath, $0.status) })
        #expect(statuses["Same.txt"] == .same)
        #expect(statuses["Different.txt"] == .different)
        #expect(statuses["Nested/Only source.txt"] == .onlySource)
        #expect(statuses["Only destination.txt"] == .onlyDestination)
        #expect(statuses["Empty"] == .onlySource)
        #expect(snapshot.sourceEntries["Same.txt"]?.sha256 == Data(SHA256.hash(data: Data("abc".utf8))))
        let plan = try VerifiedCopyPlan(snapshot: snapshot)
        #expect(plan.fileCount == 1)
        #expect(plan.directoryCount == 2)
        #expect(plan.byteCount == 6)
        #expect(plan.entries.map(\.relativePath) == ["Empty", "Nested", "Nested/Only source.txt"])
    }

    @Test("Type conflicts never produce copyable descendants")
    func conflictingParent() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Conflict/Child.txt", "child")
        try fixture.write("Conflict", "keep", in: fixture.destination)
        let snapshot = try await fixture.compare()
        #expect(snapshot.rows.first { $0.relativePath == "Conflict" }?.status == .conflict)
        #expect(snapshot.missingEntries.isEmpty)
    }

    @Test("Dotfiles and filesystem-hidden entries are excluded unless requested")
    func hiddenItems() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write(".secret/file.txt", "hidden")
        let hidden = try fixture.write("Private.txt", "hidden by flag")
        #expect(chflags(hidden.path, UInt32(UF_HIDDEN)) == 0)
        let visible = try await fixture.compare()
        #expect(visible.rows.isEmpty)
        #expect(visible.excludedHiddenCount == 2)
        let complete = try await fixture.compare(includesHidden: true)
        #expect(complete.rows.count == 3)
        #expect(complete.excludedHiddenCount == 0)
    }

    @Test("Symlinks, special files and packages are visible as skipped, never traversed")
    func skippedEntries() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let outside = try fixture.write("Outside/Secret.txt", "secret", in: fixture.root)
        try FileManager.default.createSymbolicLink(at: fixture.source.appending(path: "Link"), withDestinationURL: outside.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(atPath: fixture.source.appending(path: "Broken").path, withDestinationPath: "/missing-comparison-target")
        try fixture.write("Example.app/Contents/Info.plist", "package")
        #expect(mkfifo(fixture.source.appending(path: "Pipe").path, 0o600) == 0)
        let snapshot = try await fixture.compare()
        #expect(snapshot.rows.count == 4)
        #expect(snapshot.rows.allSatisfy { $0.status == .skipped })
        #expect(snapshot.missingEntries.isEmpty)
        #expect(snapshot.sourceEntries.values.allSatisfy { $0.sha256 == nil })
    }

    @Test("Cloud placeholder flags are recognized before any content read")
    func placeholderState() {
        var info = stat()
        info.st_mode = UInt16(S_IFREG)
        info.st_flags = UInt32(SF_DATALESS)
        #expect(ComparedFileState(info).isPlaceholder)
    }

    @Test("Unsafe roots, aliases and overlapping directories are rejected")
    func invalidRoots() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let child = fixture.source.appending(path: "Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let alias = fixture.root.appending(path: "Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.source)
        for destination in [fixture.source, child, alias, fixture.root] {
            await #expect(throws: FolderComparisonError.overlappingFolders) {
                try await FolderComparisonService().compare(source: fixture.source, destination: destination)
            }
        }
        let remote = try #require(URL(string: "https://example.com/folder"))
        await #expect(throws: FolderComparisonError.self) {
            try await FolderComparisonService().compare(source: remote, destination: fixture.destination)
        }
    }

    @Test("Enumeration has a hard item limit and rejects path traversal")
    func boundsAndPaths() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("One", "1")
        try fixture.write("Two", "2")
        await #expect(throws: FolderComparisonError.limitExceeded) {
            try await FolderComparisonService(entryLimit: 1).compare(source: fixture.source, destination: fixture.destination)
        }
        for path in ["../escape", "/absolute", "a//b", "a/./b", "a/../b", "null\0byte", ""] {
            #expect(throws: FolderComparisonError.self) { try ScopedFolderDescriptor.components(path) }
        }
    }

    @Test("Descriptor ancestry recognizes parents independently of URL spellings")
    func physicalAncestry() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let child = fixture.source.appending(path: "Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let source = try ScopedFolderDescriptor(rootURL: fixture.source)
        let nested = try ScopedFolderDescriptor(rootURL: child)
        let destination = try ScopedFolderDescriptor(rootURL: fixture.destination)
        #expect(try source.containsDirectory(nested))
        #expect(try nested.containsDirectory(source) == false)
        #expect(try source.containsDirectory(destination) == false)
        let caseAlias = fixture.root.appending(path: "sOURCE/Child")
        if FileManager.default.fileExists(atPath: caseAlias.path) {
            await #expect(throws: FolderComparisonError.overlappingFolders) {
                try await FolderComparisonService().compare(source: fixture.source, destination: caseAlias)
            }
        }
    }

    @Test("A folder changing during comparison cannot become an actionable snapshot")
    func invalidatesChangingTree() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Original.txt", "original")
        await #expect(throws: FolderComparisonError.self) {
            try await FolderComparisonService().compare(source: fixture.source, destination: fixture.destination) { progress in
                if progress.phase == "Reading folder…", progress.relativePath == fixture.destination.path {
                    do { try fixture.write("Added.txt", "new") }
                    catch { Issue.record(error) }
                }
            }
        }
    }

    @Test("Comparison cancellation returns no snapshot")
    func cancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let task = Task {
            try await FolderComparisonService().compare(source: fixture.source, destination: fixture.destination) { _ in
                // This explicitly created task, not the Swift Testing task, is cancelled.
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
