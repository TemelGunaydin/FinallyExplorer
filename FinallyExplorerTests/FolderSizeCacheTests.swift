//
//  FolderSizeCacheTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct FolderSizeCacheTests {
    @Test("Concurrent requests for one folder share a single size calculation")
    func concurrentRequestsAreCoalesced() async throws {
        let gate = FolderSizeLoadGate()
        let cache = FolderSizeCache(loader: { _ in
            await gate.beginLoad()
            await gate.waitUntilReleased()
            return 42
        })
        let directoryURL = URL(filePath: "/tmp/folder-size-cache")

        async let firstSize = cache.size(of: directoryURL)
        async let secondSize = cache.size(of: directoryURL)

        await gate.waitForFirstLoad()
        await gate.release()

        #expect(try await firstSize == 42)
        #expect(try await secondSize == 42)
        #expect(await gate.loadCount == 1)
    }

    @Test("Invalidating a folder refreshes its cached size")
    func invalidationRefreshesTheCachedSize() async throws {
        let counter = FolderSizeLoadCounter()
        let cache = FolderSizeCache(loader: { _ in
            await counter.nextSize()
        })
        let directoryURL = URL(filePath: "/tmp/folder-size-cache-refresh")

        #expect(try await cache.size(of: directoryURL) == 1)
        #expect(try await cache.size(of: directoryURL) == 1)
        #expect(await counter.loadCount == 1)

        await cache.invalidate(directoryURL)

        #expect(try await cache.size(of: directoryURL) == 2)
        #expect(await counter.loadCount == 2)
    }

    @Test("Invalidating a noncooperative in-flight load cannot publish a stale size")
    func invalidatingInFlightLoadPreventsStaleResult() async throws {
        let gate = NoncooperativeFolderSizeLoadGate()
        let cache = FolderSizeCache(loader: { _ in
            let invocation = await gate.beginLoad()

            if invocation == 1 {
                await gate.waitUntilFirstLoadIsReleased()
            }

            return Int64(invocation)
        })
        let directoryURL = URL(filePath: "/tmp/folder-size-cache-inflight")

        let staleRequest = Task {
            try await cache.size(of: directoryURL)
        }
        await gate.waitForFirstLoad()

        await cache.invalidate(directoryURL)
        await gate.releaseFirstLoad()

        await #expect(throws: CancellationError.self) {
            _ = try await staleRequest.value
        }

        #expect(try await cache.size(of: directoryURL) == 2)
        #expect(await gate.loadCount == 2)
    }

    @Test("A changed descendant refreshes only cached recursive ancestors")
    func descendantInvalidationKeepsUnrelatedFolderCacheWarm() async throws {
        let counter = FolderSizeLoadCounter()
        let cache = FolderSizeCache(loader: { _ in
            await counter.nextSize()
        })
        let parentDirectory = URL(
            filePath: "/tmp/folder-size-parent",
            directoryHint: .isDirectory
        )
        let changedChildDirectory = parentDirectory.appending(
            path: "child",
            directoryHint: .isDirectory
        )
        let unrelatedDirectory = URL(
            filePath: "/tmp/folder-size-unrelated",
            directoryHint: .isDirectory
        )

        #expect(try await cache.size(of: parentDirectory) == 1)
        #expect(try await cache.size(of: unrelatedDirectory) == 2)

        await cache.invalidateRecursively(affectedBy: [changedChildDirectory])

        #expect(try await cache.size(of: parentDirectory) == 3)
        #expect(try await cache.size(of: unrelatedDirectory) == 2)
        #expect(await counter.loadCount == 3)
    }
}

private actor FolderSizeLoadGate {
    private var didStartLoading = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var loadCount = 0

    func beginLoad() {
        loadCount += 1
        didStartLoading = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func waitForFirstLoad() async {
        guard didStartLoading == false else { return }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilReleased() async {
        guard isReleased == false else { return }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor FolderSizeLoadCounter {
    private(set) var loadCount = 0

    func nextSize() -> Int64 {
        loadCount += 1
        return Int64(loadCount)
    }
}

private actor NoncooperativeFolderSizeLoadGate {
    private var firstLoadStarted = false
    private var firstLoadReleased = false
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var loadCount = 0

    func beginLoad() -> Int {
        loadCount += 1

        if loadCount == 1 {
            firstLoadStarted = true
            firstLoadWaiters.forEach { $0.resume() }
            firstLoadWaiters.removeAll()
        }

        return loadCount
    }

    func waitForFirstLoad() async {
        guard firstLoadStarted == false else { return }

        await withCheckedContinuation { continuation in
            firstLoadWaiters.append(continuation)
        }
    }

    func waitUntilFirstLoadIsReleased() async {
        guard firstLoadReleased == false else { return }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func releaseFirstLoad() {
        firstLoadReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
