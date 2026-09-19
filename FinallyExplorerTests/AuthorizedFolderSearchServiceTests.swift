import Foundation
import Testing
@testable import FinallyExplorer

struct AuthorizedFolderSearchServiceTests {
    private static let root = URL(filePath: "/")
    private static let folder = URL(filePath: "/Volumes/Synthetic/Granted")

    @Test("Authorized roots are canonical, local, deduplicated and never widened")
    func rootSelection() throws {
        let remote = try #require(URL(string: "https://example.com/secret"))
        let roots = AuthorizedFolderSearchService.normalizedRoots([
            Self.folder, Self.folder.appending(path: "Child"), Self.folder,
            URL(filePath: "/Volumes/Synthetic/GrantedSibling"), remote
        ])
        #expect(roots == [Self.folder, URL(filePath: "/Volumes/Synthetic/GrantedSibling")])
        #expect(roots.contains(Self.folder.deletingLastPathComponent()) == false)
    }

    @Test("Preparing or granting access while idle starts no native index")
    func idleDoesNotScan() async throws {
        let pool = FFFSearchEnginePool()
        let service = AuthorizedFolderSearchService(roots: { [Self.folder] }, serviceFactory: { _ in
            HybridGlobalSearchService(enginePool: pool)
        })
        try await service.prepare(rootURL: Self.root)
        try await service.fileAccessDidChange(rootURL: Self.root)
        #expect(await pool.activeIndexCount() == 0)
        await service.shutdown()
    }

    @Test("An empty grant list never falls back to scanning the disk")
    func emptyRoots() async throws {
        let child = AuthorizedSearchFake()
        let service = AuthorizedFolderSearchService(roots: { [] }, serviceFactory: { _ in child })
        let page = try await search(service)
        #expect(page.results.isEmpty)
        #expect(page.message?.text.contains("File Access") == true)
        #expect(await child.requestedRoots.isEmpty)
        await service.shutdown()
    }

    @Test("Unavailable roots preserve other results and expose a partial-search notice")
    func partialFailure() async throws {
        let good = AuthorizedSearchFake(page: Self.page("Needle.txt"))
        let bad = AuthorizedSearchFake(fails: true)
        let other = URL(filePath: "/Volumes/Disconnected")
        let service = AuthorizedFolderSearchService(roots: { [Self.folder, other] }, serviceFactory: {
            $0 == Self.folder ? good : bad
        })
        let page = try await search(service)
        #expect(page.results.map(\.item.name) == ["Needle.txt"])
        #expect(page.message?.text.contains("Disconnected") == true)
        #expect(page.isIndexWarming == false)
        await service.shutdown()
    }

    @Test("Grant changes retire old root services and query the newly granted root")
    func changedRoots() async throws {
        let roots = AuthorizedRootsFake([Self.folder])
        let old = AuthorizedSearchFake(page: Self.page("Old.txt"))
        let new = AuthorizedSearchFake(page: Self.page("New.txt"))
        let next = URL(filePath: "/Volumes/NewGrant")
        let service = AuthorizedFolderSearchService(roots: { await roots.urls }, serviceFactory: {
            $0 == Self.folder ? old : new
        })
        _ = try await search(service)
        await roots.set([next])
        try await service.fileAccessDidChange(rootURL: Self.root)
        #expect(await old.shutdownCount == 1)
        #expect(await new.requestedRoots.isEmpty)
        let page = try await search(service)
        #expect(page.results.map(\.item.name) == ["New.txt"])
        #expect(await new.requestedRoots == [next])
        await service.shutdown()
        #expect(await new.shutdownCount == 1)
    }

    @Test("Shutdown invalidates an in-flight provider before creating a child service")
    func shutdownDuringRootLookup() async throws {
        let gate = AuthorizedSearchGate()
        let child = AuthorizedSearchFake()
        let service = AuthorizedFolderSearchService(roots: {
            await gate.pause()
            return [Self.folder]
        }, serviceFactory: { _ in child })
        let request = Task { try await search(service) }
        await gate.waitUntilEntered()
        await service.shutdown()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await child.requestedRoots.isEmpty)
    }

    @Test("Cancellation cannot publish a completed child page")
    func cancelledSearch() async throws {
        let gate = AuthorizedSearchGate()
        let child = AuthorizedSearchFake(page: Self.page("Needle.txt"), gate: gate)
        let service = AuthorizedFolderSearchService(roots: { [Self.folder] }, serviceFactory: { _ in child })
        let request = Task { try await search(service) }
        await gate.waitUntilEntered()
        request.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await request.value }
        await service.shutdown()
    }

    @Test("Spotlight matches do not hide files from directly granted roots")
    func combinesSpotlightAndGrants() async throws {
        let local = AuthorizedSearchFake(page: Self.page("Needle-local.txt"))
        let service = HybridGlobalSearchService(
            spotlightService: AuthorizedSpotlightFake(), authorizedSearch: local
        )
        let page = try await search(service)
        #expect(Set(page.results.map(\.item.name)) == ["Needle-local.txt", "Needle-spotlight.txt"])
        #expect(await local.requestedRoots == [Self.root])
        await service.shutdown()
        #expect(await local.shutdownCount == 1)
    }

    @Test("Merged results have stable IDs, keep distinct content lines, and are capped")
    func mergeIdentityAndLimit() {
        let page = Self.page("Needle.txt")
        let renamedID = GlobalSearchPage(results: page.results.map {
            ExplorerSearchResult(id: "different", item: $0.item, relativePath: $0.relativePath, contentMatch: nil)
        }, message: nil)
        let merged = AuthorizedFolderSearchService.merged([page, renamedID], query: "Needle", scope: .names)
        #expect(merged.results.count == 1)
        #expect(merged.results.first?.id == AuthorizedFolderSearchService.merged([renamedID], query: "Needle", scope: .names).results.first?.id)
        let lines = [UInt64(1), 2, 1].map { line in
            ExplorerSearchResult(id: "line\(line)", item: page.results[0].item, relativePath: "Needle.txt",
                contentMatch: ExplorerContentMatch(lineContent: "Needle", lineNumber: line, column: 0,
                    matchByteRanges: [0..<6], contextBefore: [], contextAfter: [], isDefinition: false))
        }
        let content = AuthorizedFolderSearchService.merged(
            [GlobalSearchPage(results: lines, message: nil)], query: "Needle", scope: .contents
        )
        #expect(content.results.compactMap { $0.contentMatch?.lineNumber } == [1, 2])
        let limited = AuthorizedFolderSearchService.merged((0..<140).map { Self.page("Needle\($0).txt") }, query: "Needle", scope: .names)
        #expect(limited.results.count == 120)
        #expect(limited.message != nil)
    }

    @Test("An unavailable or empty Spotlight index uses authorized roots, not a disk scan", arguments: [false, true])
    func authorizedFallback(spotlightFails: Bool) async throws {
        let child = AuthorizedSearchFake(page: Self.page("Needle.txt"))
        let pool = FFFSearchEnginePool()
        let service = HybridGlobalSearchService(enginePool: pool,
            spotlightService: AuthorizedSpotlightFake(empty: true, fails: spotlightFails), authorizedSearch: child)
        let page = try await search(service)
        #expect(page.results.map(\.item.name) == ["Needle.txt"])
        #expect(await child.requestedRoots == [Self.root])
        #expect(await pool.activeIndexCount() == 0)
        await service.shutdown()
    }

    @Test("Global contents and regex are routed directly to granted roots")
    func authorizedContentRouting() async throws {
        let child = AuthorizedSearchFake(page: Self.page("Needle.txt"))
        let pool = FFFSearchEnginePool()
        let service = HybridGlobalSearchService(enginePool: pool, authorizedSearch: child)
        _ = try await service.search(rootURL: Self.root, query: "token-[0-9]+", scope: .contents, contentMode: .regex)
        #expect(await child.requestedRoots == [Self.root])
        #expect(await child.contentModes == [.regex])
        #expect(await pool.activeIndexCount() == 0)
        await service.shutdown()
    }

    @Test("Shutdown and access changes reject in-flight child results", arguments: [false, true])
    func invalidatedChildResult(shutdown: Bool) async throws {
        let gate = AuthorizedSearchGate()
        let child = AuthorizedSearchFake(page: Self.page("Needle.txt"), gate: gate)
        let roots = AuthorizedRootsFake([Self.folder])
        let service = AuthorizedFolderSearchService(roots: { await roots.urls }, serviceFactory: { _ in child })
        let request = Task { try await search(service) }
        await gate.waitUntilEntered()
        if shutdown { await service.shutdown() }
        else {
            await roots.set([])
            try await service.fileAccessDidChange(rootURL: Self.root)
        }
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await child.shutdownCount == 1)
        await service.shutdown()
    }

    @Test("Direct native indexing searches names and grep, then releases its lease")
    func nativeNarrowRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FEAuthorizedSearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "Needle.json")
        try Data("{\"value\":\"authorized-token-7319\"}\n".utf8).write(to: file)
        let pool = FFFSearchEnginePool()
        let service = AuthorizedFolderSearchService(roots: { [root] }, serviceFactory: { _ in
            HybridGlobalSearchService(enginePool: pool)
        })
        do {
            _ = try await search(service)
            try await service.waitForInitialScan(rootURL: Self.root)
            let names = try await search(service)
            #expect(names.results.map(\.item.url) == [file.standardizedFileURL.resolvingSymlinksInPath()])
            for mode in [FFFContentSearchMode.plain, .regex] {
                let page = try await service.search(rootURL: Self.root,
                    query: mode == .regex ? "authorized-token-[0-9]+" : "authorized-token-7319",
                    scope: .contents, contentMode: mode)
                #expect(page.results.first?.contentMatch?.lineNumber == 1)
                #expect(page.results.first?.item.name == "Needle.json")
            }
            #expect(await pool.activeIndexCount() == 1)
            await service.shutdown()
            #expect(await pool.activeIndexCount() == 0)
        } catch {
            await service.shutdown()
            throw error
        }
    }

    private func search(_ service: any GlobalSearchServicing) async throws -> GlobalSearchPage {
        try await service.search(rootURL: Self.root, query: "Needle", scope: .names, contentMode: .plain)
    }

    private static func page(_ name: String) -> GlobalSearchPage {
        GlobalSearchPage(results: [ExplorerSearchResult(id: name,
            item: FileItem(url: folder.appending(path: name), isDirectory: false, isImage: false, fileSize: 10, modificationDate: nil),
            relativePath: name, contentMatch: nil)], message: nil)
    }
}

private actor AuthorizedRootsFake {
    var urls: [URL]
    init(_ urls: [URL]) { self.urls = urls }
    func set(_ urls: [URL]) { self.urls = urls }
}

private actor AuthorizedSearchFake: GlobalSearchServicing {
    enum Failure: Error { case unavailable }
    let page: GlobalSearchPage
    let fails: Bool
    let gate: AuthorizedSearchGate?
    var requestedRoots: [URL] = []
    var contentModes: [FFFContentSearchMode] = []
    var shutdownCount = 0
    init(page: GlobalSearchPage = GlobalSearchPage(results: [], message: nil),
         fails: Bool = false, gate: AuthorizedSearchGate? = nil) {
        self.page = page; self.fails = fails; self.gate = gate
    }
    func prepare(rootURL: URL) async throws { }
    func search(rootURL: URL, query: String, scope: ExplorerSearchScope,
                contentMode: FFFContentSearchMode) async throws -> GlobalSearchPage {
        requestedRoots.append(rootURL)
        contentModes.append(contentMode)
        await gate?.pause()
        if fails { throw Failure.unavailable }
        return page
    }
    func shutdown() async { shutdownCount += 1 }
}

private actor AuthorizedSearchGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        waiter?.resume(); waiter = nil
        await withCheckedContinuation { pending = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume() { pending?.resume(); pending = nil }
}

private struct AuthorizedSpotlightFake: SpotlightGlobalSearchServicing {
    var empty = false
    var fails = false
    func search(rootURL: URL, query: String, maximumCandidateCount: Int) async throws -> SpotlightGlobalSearchService.Page {
        if fails { throw AuthorizedSearchFake.Failure.unavailable }
        if empty { return SpotlightGlobalSearchService.Page(hits: [], isTruncated: false) }
        return SpotlightGlobalSearchService.Page(hits: [.init(url: URL(filePath: "/Volumes/Synthetic/Needle-spotlight.txt"),
            isDirectory: false, isImage: false, byteSize: 10, modificationDate: nil)], isTruncated: false)
    }
}
