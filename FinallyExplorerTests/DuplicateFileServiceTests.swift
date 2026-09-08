import Darwin
import Foundation
import Testing
@testable import FinallyExplorer

struct DuplicateFileServiceTests {
    @Test("Duplicate detection uses contents across different names, extensions and dates")
    func exactData() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "same")
        let second = try fixture.write("Nested/B.json", "same")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: second.path)
        try fixture.write("C.txt", "diff")
        try fixture.write("Unique.txt", "unique length")
        let result = try await DuplicateFileService().scan(rootURL: fixture.source)
        #expect(result.groups.count == 1)
        #expect(result.groups.first?.files.map(\.relativePath) == ["A.txt", "Nested/B.json"])
        #expect(result.hashedFileCount == 3)
        #expect(result.entries["Unique.txt"]?.sha256 == nil)
        #expect(result.duplicateBytes == 4)
        #expect(result.groups.first?.fileSize == 4)
    }

    @Test("Hidden files are opt-in, empty files and hard links are excluded")
    func skippedFiles() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Visible.txt", "same")
        try fixture.write(".Hidden.txt", "same")
        let linked = try fixture.write("Hard.txt", "same")
        try FileManager.default.linkItem(at: linked, to: fixture.source.appending(path: "Hard copy.txt"))
        try fixture.write("Empty.txt", "")
        let result = try await DuplicateFileService().scan(rootURL: fixture.source)
        #expect(result.groups.isEmpty)
        #expect(result.excludedHiddenCount == 1)
        #expect(result.skipped.count == 3)
        #expect(result.hashedFileCount == 0)
        let complete = try await DuplicateFileService().scan(rootURL: fixture.source, includesHidden: true)
        #expect(complete.groups.first?.files.map(\.relativePath) == [".Hidden.txt", "Visible.txt"])
        #expect(complete.duplicateBytes == 4)
    }

    @Test("Resource forks, symlinks, special files and packages are not removable duplicates")
    func metadataAndLinks() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let forked = try fixture.write("Forked.txt", "same")
        let fork = Data("different resource data".utf8)
        let code = fork.withUnsafeBytes { bytes in
            setxattr(forked.path, XATTR_RESOURCEFORK_NAME, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(code == 0)
        try fixture.write("Plain.txt", "same")
        try FileManager.default.createSymbolicLink(at: fixture.source.appending(path: "Link.txt"), withDestinationURL: forked)
        try fixture.write("Example.app/Contents/File.txt", "same")
        #expect(mkfifo(fixture.source.appending(path: "Pipe").path, 0o600) == 0)
        let result = try await DuplicateFileService().scan(rootURL: fixture.source)
        #expect(result.groups.isEmpty)
        #expect(result.skipped.count == 4)
        #expect(result.entries["Example.app/Contents/File.txt"] == nil)
        #expect(result.hashedFileCount == 1)
    }

    @Test("Entry limits and unsafe roots stop a scan without returning actionable results")
    func limits() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "same")
        try fixture.write("B.txt", "same")
        await #expect(throws: FolderComparisonError.limitExceeded) {
            try await DuplicateFileService(entryLimit: 1).scan(rootURL: fixture.source)
        }
        await #expect(throws: FolderComparisonError.invalidFolders) {
            try await DuplicateFileService().scan(rootURL: URL(filePath: "/"))
        }
    }

    @Test("Cancelling during enumeration never returns a snapshot", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("A.txt", "same")
        let gate = FolderComparisonTestGate()
        let task = Task { try await DuplicateFileService().scan(rootURL: fixture.source) { _ in await gate.pause() } }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
