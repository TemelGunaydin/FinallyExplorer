import Foundation
import Testing
@testable import FinallyExplorer

struct ArchiveCompressionTests {
    @Test("Sandbox-compatible ZIP round-trips a folder, hidden files, and Unicode names", .timeLimit(.minutes(1)))
    func folderRoundTrip() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        try fixture.write("Project/Notes/Résumé.txt", "Archive contents")
        try fixture.write("Project/.hidden", "Hidden contents")
        let source = fixture.source.appending(path: "Project")
        try FileManager.default.createSymbolicLink(atPath: source.appending(path: "NotesLink").path, withDestinationPath: "Notes")
        let outcome = try await FileOperationService().compressItem(at: source)
        let archive = outcome.destinationURL
        #expect(archive.lastPathComponent == "Project.zip")
        #expect(outcome.didChange)
        try await extract(archive, into: fixture.destination)
        #expect(try String(contentsOf: fixture.destination.appending(path: "Project/Notes/Résumé.txt"), encoding: .utf8) == "Archive contents")
        #expect(try String(contentsOf: fixture.destination.appending(path: "Project/.hidden"), encoding: .utf8) == "Hidden contents")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.destination.appending(path: "Project/NotesLink").path) == "Notes")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.source.path).sorted() == ["Project", "Project.zip"])
    }

    @Test("Compressing twice preserves the original and chooses a new archive name", .timeLimit(.minutes(1)))
    func collision() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "First contents")
        let first = try await FileOperationService().compressItem(at: file).destinationURL
        let originalArchive = try Data(contentsOf: first)
        try Data("New contents".utf8).write(to: file)
        let second = try await FileOperationService().compressItem(at: file).destinationURL
        #expect(first != second)
        #expect(try Data(contentsOf: first) == originalArchive)
        try await extract(second, into: fixture.destination)
        #expect(try String(contentsOf: fixture.destination.appending(path: "Report.txt"), encoding: .utf8) == "New contents")
    }

    @Test("Cancelled compression does not create an archive or alter its source", .timeLimit(.minutes(1)))
    func cancelled() async throws {
        let fixture = try FolderComparisonTestFixture()
        defer { fixture.remove() }
        let file = try fixture.write("Report.txt", "Unchanged")
        let gate = FolderComparisonTestGate()
        let task = Task {
            await gate.pause()
            return try await FileOperationService().compressItem(at: file)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.source.path) == ["Report.txt"])
        #expect(try String(contentsOf: file, encoding: .utf8) == "Unchanged")
    }

    @Test("Large diagnostics drain completely without retaining unbounded output", .timeLimit(.minutes(1)))
    func boundedDiagnostics() async throws {
        let pipe = Pipe()
        let payload = Data(repeating: 65, count: 2_000_000)
        async let writing: Void = write(payload, to: pipe.fileHandleForWriting)
        let prefix = await ArchiveProcessOutput.collect(from: pipe.fileHandleForReading, limit: 4096)
        try await writing
        #expect(prefix == payload.prefix(4096))
    }

    private func write(_ data: Data, to handle: FileHandle) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .utility).async {
                defer { try? handle.close() }
                do { try handle.write(contentsOf: data); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    @concurrent private func extract(_ archive: URL, into destination: URL) async throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        try? pipe.fileHandleForWriting.close()
        let diagnostics = await ArchiveProcessOutput.collect(from: pipe.fileHandleForReading)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(String(decoding: diagnostics, as: UTF8.self))")
    }
}
