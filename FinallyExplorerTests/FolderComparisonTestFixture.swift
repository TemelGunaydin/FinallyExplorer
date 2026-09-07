import Foundation
@testable import FinallyExplorer

nonisolated struct FolderComparisonTestFixture: Sendable {
    let root: URL
    let source: URL
    let destination: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FinallyExplorer-Comparison-\(UUID().uuidString)", directoryHint: .isDirectory)
        source = root.appending(path: "Source", directoryHint: .isDirectory)
        destination = root.appending(path: "Destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ path: String, _ text: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? source).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func compare(includesHidden: Bool = false) async throws -> FolderComparisonSnapshot {
        try await FolderComparisonService().compare(source: source, destination: destination, includesHidden: includesHidden)
    }

    func plan() async throws -> VerifiedCopyPlan { try VerifiedCopyPlan(snapshot: await compare()) }

    func destinationNames() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted() }
}

actor FolderComparisonTestGate {
    private var entered = false
    private var released = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        if released == false { await withCheckedContinuation { releaseWaiter = $0 } }
    }

    func waitUntilEntered() async {
        if entered == false { await withCheckedContinuation { enteredWaiter = $0 } }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
