//
//  TerminalApplicationServiceTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct TerminalApplicationServiceTests {
    @Test("An arbitrary shell application is discovered without an allowlist")
    func discoversUnknownTerminalApplication() throws {
        let candidate = terminalCandidate(
            name: "Orbit Shell",
            bundleIdentifier: "dev.example.orbit-shell"
        )
        let workspace = TerminalWorkspaceMock(candidates: [candidate])

        let applications = TerminalApplicationService(workspace: workspace)
            .installedApplications()
        let application = try #require(applications.first)

        #expect(applications.count == 1)
        #expect(application.name == "Orbit Shell")
        #expect(application.bundleIdentifier == "dev.example.orbit-shell")
        #expect(application.applicationURL == candidate.applicationURL)
    }

    @Test("Only applications declaring the Shell document role are classified as terminals")
    func classifiesShellDocumentRole() {
        #expect(
            TerminalApplicationClassifier.isTerminal(
                documentTypeRoles: ["Editor", "Viewer"]
            ) == false
        )
        #expect(
            TerminalApplicationClassifier.isTerminal(
                documentTypeRoles: ["Editor", "sHeLl"]
            )
        )
        #expect(
            TerminalApplicationClassifier.isTerminal(
                documentTypeRoles: ["  SHELL\n"]
            )
        )
        #expect(
            TerminalApplicationClassifier.isTerminal(documentTypeRoles: []) == false
        )
    }

    @Test("Malformed application bundles cannot become terminal menu entries")
    func rejectsMalformedApplicationBundles() throws {
        let corruptBundleURL = try makeTerminalApplicationBundle(
            infoData: Data("not a property list".utf8)
        )
        defer { try? FileManager.default.removeItem(at: corruptBundleURL) }

        let malformedMetadataURL = try makeTerminalApplicationBundle(
            info: terminalBundleInfo(
                documentTypes: "Shell is not a document-type array"
            )
        )
        defer { try? FileManager.default.removeItem(at: malformedMetadataURL) }

        #expect(
            SystemTerminalWorkspace.terminalApplicationCandidate(
                at: corruptBundleURL
            ) == nil
        )
        #expect(
            SystemTerminalWorkspace.terminalApplicationCandidate(
                at: malformedMetadataURL
            ) == nil
        )
    }

    @Test("Bundle discovery trims shell metadata and ignores blank display names")
    func parsesDefensiveBundleMetadata() throws {
        let bundleURL = try makeTerminalApplicationBundle(
            info: terminalBundleInfo(
                displayName: " \n ",
                bundleName: "  Fallback Shell  ",
                documentTypes: [["CFBundleTypeRole": " sHeLl\n"]]
            )
        )
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let candidate = try #require(
            SystemTerminalWorkspace.terminalApplicationCandidate(at: bundleURL)
        )

        #expect(candidate.name == "Fallback Shell")
        #expect(candidate.bundleIdentifier == "dev.finallyexplorer.mock-terminal")
        #expect(candidate.applicationURL == bundleURL)
    }

    @Test("Discovered applications are deduplicated and sorted by display name")
    func deduplicatesAndSortsApplications() {
        let pathOnlyURL = URL(filePath: "/Mock/PathTerm.app")
        let workspace = TerminalWorkspaceMock(candidates: [
            terminalCandidate(
                name: "Zephyr",
                bundleIdentifier: "dev.example.zephyr"
            ),
            terminalCandidate(
                name: "alphaTerm",
                bundleIdentifier: "dev.example.alpha"
            ),
            TerminalApplicationCandidate(
                name: "Duplicate Alpha",
                bundleIdentifier: "dev.example.alpha",
                applicationURL: URL(filePath: "/Mock/OtherAlpha.app")
            ),
            TerminalApplicationCandidate(
                name: " \n",
                bundleIdentifier: " \n",
                applicationURL: pathOnlyURL
            ),
            TerminalApplicationCandidate(
                name: "Duplicate Path",
                bundleIdentifier: "dev.example.path-alias",
                applicationURL: pathOnlyURL
            )
        ])

        let applications = TerminalApplicationService(workspace: workspace)
            .installedApplications()

        #expect(applications.map(\.name) == ["alphaTerm", "PathTerm", "Zephyr"])
        #expect(
            applications.map(\.bundleIdentifier) == [
                "dev.example.alpha",
                nil,
                "dev.example.zephyr"
            ]
        )
    }

    @Test("Application ordering is deterministic when names compare equally")
    func deterministicallyOrdersEqualNames() {
        let candidates = [
            TerminalApplicationCandidate(
                name: "term",
                bundleIdentifier: "dev.example.z",
                applicationURL: URL(filePath: "/Mock/Z.app")
            ),
            TerminalApplicationCandidate(
                name: "Term",
                bundleIdentifier: "dev.example.b",
                applicationURL: URL(filePath: "/Mock/B.app")
            ),
            TerminalApplicationCandidate(
                name: "Term",
                bundleIdentifier: "dev.example.a",
                applicationURL: URL(filePath: "/Mock/A.app")
            )
        ]

        let forward = TerminalApplicationService(
            workspace: TerminalWorkspaceMock(candidates: candidates)
        ).installedApplications()
        let reversed = TerminalApplicationService(
            workspace: TerminalWorkspaceMock(candidates: Array(candidates.reversed()))
        ).installedApplications()
        let expectedIdentifiers: [String?] = [
            "dev.example.a",
            "dev.example.b",
            "dev.example.z"
        ]

        #expect(forward.map(\.bundleIdentifier) == expectedIdentifiers)
        #expect(reversed.map(\.bundleIdentifier) == expectedIdentifiers)
    }

    @Test("Refreshing discovers a terminal installed while the app is running")
    func coordinatorRefreshesInstalledApplications() {
        let workspace = TerminalWorkspaceMock(candidates: [
            terminalCandidate(
                name: "Ghostty",
                bundleIdentifier: "com.mitchellh.ghostty"
            )
        ])
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)

        #expect(coordinator.installedApplications.map(\.name) == ["Ghostty"])

        workspace.candidates.append(
            terminalCandidate(
                name: "FutureTerm",
                bundleIdentifier: "dev.future.terminal"
            )
        )
        coordinator.refresh()

        #expect(
            coordinator.installedApplications.map(\.name) == ["FutureTerm", "Ghostty"]
        )
    }

    @Test("Opening forwards the folder and the currently resolved application URL")
    func opensDirectoryWithSelectedApplication() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let currentApplicationURL = URL(filePath: "/Mock/Current/Ghostty.app")
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.mitchellh.ghostty": currentApplicationURL]
        )
        let application = TerminalApplication(
            name: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty",
            applicationURL: URL(filePath: "/Mock/Previous/Ghostty.app")
        )

        try await TerminalApplicationService(workspace: workspace).open(
            directoryURL: directoryURL,
            in: application
        )

        #expect(
            workspace.openRequests == [
                TerminalOpenRequest(
                    directoryURL: directoryURL,
                    applicationURL: currentApplicationURL
                )
            ]
        )
    }

    @Test("A terminal without a usable bundle identifier opens by its installed path")
    func opensPathOnlyApplication() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        let applicationRootURL = try makeTerminalTestDirectory()
        let applicationURL = applicationRootURL.appending(path: "Path Shell.app")
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: applicationRootURL)
        }
        let workspace = TerminalWorkspaceMock()
        let application = TerminalApplication(
            name: "Path Shell",
            bundleIdentifier: " \n",
            applicationURL: applicationURL
        )

        try await TerminalApplicationService(workspace: workspace).open(
            directoryURL: directoryURL,
            in: application
        )

        #expect(
            workspace.openRequests == [
                TerminalOpenRequest(
                    directoryURL: directoryURL,
                    applicationURL: applicationURL
                )
            ]
        )
    }

    @Test("A regular file masquerading as an application is rejected")
    func rejectsPathOnlyApplicationFile() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        let rootURL = try makeTerminalTestDirectory()
        let applicationURL = rootURL.appending(path: "NotAnApp.app")
        try Data().write(to: applicationURL)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let workspace = TerminalWorkspaceMock()
        let application = TerminalApplication(
            name: "Not An App",
            bundleIdentifier: nil,
            applicationURL: applicationURL
        )

        await #expect(
            throws: TerminalApplicationError.applicationNotFound(name: "Not An App")
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: directoryURL,
                in: application
            )
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("Nonlocal folder URLs are rejected even when their path exists locally")
    func rejectsNonlocalDirectoryURLs() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": URL(filePath: "/Mock/Terminal.app")]
        )

        var remoteFileComponents = try #require(
            URLComponents(url: directoryURL, resolvingAgainstBaseURL: false)
        )
        remoteFileComponents.host = "files.example.invalid"
        let remoteFileURL = try #require(remoteFileComponents.url)

        var webComponents = remoteFileComponents
        webComponents.scheme = "https"
        let webURL = try #require(webComponents.url)

        for invalidURL in [remoteFileURL, webURL] {
            await #expect(
                throws: TerminalApplicationError.invalidFolderURL(
                    url: invalidURL.absoluteString
                )
            ) {
                try await TerminalApplicationService(workspace: workspace).open(
                    directoryURL: invalidURL,
                    in: terminalApplication()
                )
            }
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("A resolver cannot redirect an open to a remote application URL")
    func rejectsRemoteResolvedApplicationURL() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        let applicationRootURL = try makeTerminalTestDirectory()
        let applicationURL = applicationRootURL.appending(path: "Terminal.app")
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: applicationRootURL)
        }

        var remoteComponents = try #require(
            URLComponents(url: applicationURL, resolvingAgainstBaseURL: false)
        )
        remoteComponents.host = "apps.example.invalid"
        let remoteApplicationURL = try #require(remoteComponents.url)
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": remoteApplicationURL]
        )

        await #expect(
            throws: TerminalApplicationError.applicationNotFound(name: "Terminal")
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: directoryURL,
                in: terminalApplication()
            )
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("The coordinator exposes a task that completes after opening finishes")
    func coordinatorOpenCompletesDeterministically() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let applicationURL = URL(filePath: "/Mock/Current/OrbitShell.app")
        let application = TerminalApplication(
            name: "Orbit Shell",
            bundleIdentifier: "dev.example.orbit-shell",
            applicationURL: applicationURL
        )
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["dev.example.orbit-shell": applicationURL]
        )
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)

        let task = try #require(coordinator.open(directoryURL, in: application))
        #expect(coordinator.isOpening)
        await task.value

        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
        #expect(
            workspace.openRequests == [
                TerminalOpenRequest(
                    directoryURL: directoryURL,
                    applicationURL: applicationURL
                )
            ]
        )
    }

    @Test("A failed open is fully cleared before the next successful attempt")
    func coordinatorClearsStaleFailureState() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let applicationURL = URL(filePath: "/Mock/Current/Terminal.app")
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": applicationURL],
            openError: TerminalWorkspaceTestError.openFailed
        )
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)

        let failedTask = try #require(
            coordinator.open(directoryURL, in: terminalApplication())
        )
        await failedTask.value
        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented)
        #expect(coordinator.errorMessage.isEmpty == false)

        workspace.openError = nil
        let successfulTask = try #require(
            coordinator.open(directoryURL, in: terminalApplication())
        )
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
        await successfulTask.value

        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
    }

    @Test("Refreshing during an open preserves single-flight state and discovery updates")
    func refreshDuringOpenDoesNotCorruptCoordinatorState() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let gate = TerminalOpenGate()
        let applicationURL = URL(filePath: "/Mock/Current/Ghostty.app")
        let application = TerminalApplication(
            name: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty",
            applicationURL: applicationURL
        )
        let workspace = TerminalWorkspaceMock(
            candidates: [
                terminalCandidate(
                    name: "Ghostty",
                    bundleIdentifier: "com.mitchellh.ghostty"
                )
            ],
            applicationURLs: ["com.mitchellh.ghostty": applicationURL],
            openGate: gate
        )
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)
        let task = try #require(coordinator.open(directoryURL, in: application))
        await gate.waitUntilStarted()

        workspace.candidates = [
            terminalCandidate(
                name: "FutureTerm",
                bundleIdentifier: "dev.future.terminal"
            )
        ]
        coordinator.refresh()

        #expect(coordinator.installedApplications.map(\.name) == ["FutureTerm"])
        #expect(coordinator.isOpening)
        #expect(coordinator.open(directoryURL, in: application) == nil)

        await gate.release()
        await task.value
        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
    }

    @Test("Immediate cancellation prevents workspace side effects and clears opening state")
    func immediateCancellationCleansUp() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let applicationURL = URL(filePath: "/Mock/Current/Terminal.app")
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": applicationURL]
        )
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)
        let task = try #require(
            coordinator.open(directoryURL, in: terminalApplication())
        )

        task.cancel()
        await task.value

        #expect(workspace.openRequests.isEmpty)
        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
    }

    @Test("Cancellation after a noncooperative workspace returns still wins")
    func cancellationAfterWorkspaceSuspensionCleansUp() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let gate = TerminalOpenGate()
        let applicationURL = URL(filePath: "/Mock/Current/Terminal.app")
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": applicationURL],
            openGate: gate
        )
        let coordinator = TerminalApplicationCoordinator(workspace: workspace)
        let task = try #require(
            coordinator.open(directoryURL, in: terminalApplication())
        )
        await gate.waitUntilStarted()

        task.cancel()
        await gate.release()
        await task.value

        #expect(workspace.openRequests.count == 1)
        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
        #expect(coordinator.errorMessage.isEmpty)
    }

    @Test("A missing folder is rejected before the workspace is called")
    func rejectsMissingFolder() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: "FinallyExplorer-Terminal-Missing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": URL(filePath: "/Mock/Terminal.app")]
        )

        await #expect(
            throws: TerminalApplicationError.folderNotFound(path: directoryURL.path)
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: directoryURL,
                in: terminalApplication()
            )
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("A file cannot be opened as a terminal working directory")
    func rejectsFileDestination() async throws {
        let rootURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "item.txt")
        try Data().write(to: fileURL)
        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": URL(filePath: "/Mock/Terminal.app")]
        )

        await #expect(
            throws: TerminalApplicationError.destinationIsNotFolder(path: fileURL.path)
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: fileURL,
                in: terminalApplication()
            )
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("A terminal removed after discovery reports a clear error")
    func rejectsRemovedApplication() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspace = TerminalWorkspaceMock()

        await #expect(
            throws: TerminalApplicationError.applicationNotFound(name: "Terminal")
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: directoryURL,
                in: terminalApplication()
            )
        }
        #expect(workspace.openRequests.isEmpty)
    }

    @Test("Workspace failures retain the selected terminal and folder context")
    func mapsWorkspaceOpenFailure() async throws {
        let directoryURL = try makeTerminalTestDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspace = TerminalWorkspaceMock(
            applicationURLs: ["com.apple.Terminal": URL(filePath: "/Mock/Terminal.app")],
            openError: TerminalWorkspaceTestError.openFailed
        )

        await #expect(
            throws: TerminalApplicationError.openFailed(
                applicationName: "Terminal",
                path: directoryURL.path,
                reason: "The mock terminal could not be opened."
            )
        ) {
            try await TerminalApplicationService(workspace: workspace).open(
                directoryURL: directoryURL,
                in: terminalApplication()
            )
        }
    }

    @Test("A remembered installed terminal is resolved and can be forgotten")
    func persistsPreferredTerminalChoice() throws {
        let terminal = terminalCandidate(
            name: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty"
        )
        let preferenceStore = TerminalPreferenceStoreMock(
            applicationID: "com.mitchellh.ghostty"
        )
        let coordinator = TerminalApplicationCoordinator(
            workspace: TerminalWorkspaceMock(candidates: [terminal]),
            preferenceStore: preferenceStore
        )

        #expect(coordinator.preferredApplication?.name == "Ghostty")

        let anotherTerminal = TerminalApplication(
            name: "Orbit",
            bundleIdentifier: "dev.example.orbit",
            applicationURL: URL(filePath: "/Mock/Orbit.app")
        )
        coordinator.remember(anotherTerminal)
        #expect(coordinator.preferredApplicationID == "dev.example.orbit")
        #expect(preferenceStore.savedApplicationIDs == ["dev.example.orbit"])

        coordinator.forgetPreferredApplication()
        #expect(coordinator.preferredApplicationID == nil)
        #expect(preferenceStore.savedApplicationIDs == ["dev.example.orbit", nil])
    }

    @Test("A stale remembered terminal never opens a different application")
    func stalePreferenceRequiresAnotherChoice() {
        let preferenceStore = TerminalPreferenceStoreMock(
            applicationID: "dev.removed.terminal"
        )
        let coordinator = TerminalApplicationCoordinator(
            workspace: TerminalWorkspaceMock(candidates: [
                terminalCandidate(
                    name: "Terminal",
                    bundleIdentifier: "com.apple.Terminal"
                )
            ]),
            preferenceStore: preferenceStore
        )

        #expect(coordinator.preferredApplication == nil)
        #expect(
            coordinator.openPreferred(
                URL(filePath: "/tmp", directoryHint: .isDirectory)
            ) == nil
        )
    }

    private func terminalApplication() -> TerminalApplication {
        TerminalApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            applicationURL: URL(filePath: "/Mock/Terminal.app")
        )
    }

    private func terminalCandidate(
        name: String,
        bundleIdentifier: String?
    ) -> TerminalApplicationCandidate {
        TerminalApplicationCandidate(
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: URL(filePath: "/Mock/\(name).app")
        )
    }
}

private struct TerminalOpenRequest: Equatable {
    let directoryURL: URL
    let applicationURL: URL
}

@MainActor
private final class TerminalPreferenceStoreMock: TerminalPreferenceStoring {
    private let applicationID: String?
    private(set) var savedApplicationIDs: [String?] = []

    init(applicationID: String?) {
        self.applicationID = applicationID
    }

    func loadPreferredApplicationID() -> String? {
        applicationID
    }

    func savePreferredApplicationID(_ applicationID: String?) {
        savedApplicationIDs.append(applicationID)
    }
}

@MainActor
private final class TerminalWorkspaceMock: TerminalWorkspace {
    var candidates: [TerminalApplicationCandidate]
    var applicationURLs: [String: URL]
    var openError: (any Error)?
    private(set) var openRequests: [TerminalOpenRequest] = []

    private let openGate: TerminalOpenGate?

    init(
        candidates: [TerminalApplicationCandidate] = [],
        applicationURLs: [String: URL] = [:],
        openError: (any Error)? = nil,
        openGate: TerminalOpenGate? = nil
    ) {
        self.candidates = candidates
        self.applicationURLs = applicationURLs
        self.openError = openError
        self.openGate = openGate
    }

    func terminalApplicationCandidates() -> [TerminalApplicationCandidate] {
        candidates
    }

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        applicationURLs[bundleIdentifier]
    }

    func openDirectory(
        _ directoryURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        openRequests.append(
            TerminalOpenRequest(
                directoryURL: directoryURL,
                applicationURL: applicationURL
            )
        )

        if let openGate {
            await openGate.startAndWaitForRelease()
        }

        if let openError {
            throw openError
        }
    }
}

private actor TerminalOpenGate {
    private var hasStarted = false
    private var hasReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard hasStarted == false else { return }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func startAndWaitForRelease() async {
        hasStarted = true

        let pendingStartWaiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingStartWaiters {
            waiter.resume()
        }

        guard hasReleased == false else { return }

        await withCheckedContinuation { continuation in
            if hasReleased {
                continuation.resume()
            } else {
                releaseWaiters.append(continuation)
            }
        }
    }

    func release() {
        hasReleased = true
        let pendingReleaseWaiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingReleaseWaiters {
            waiter.resume()
        }
    }
}

private nonisolated enum TerminalWorkspaceTestError: LocalizedError {
    case openFailed

    var errorDescription: String? {
        "The mock terminal could not be opened."
    }
}

private func makeTerminalTestDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorer-Terminal-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    return directoryURL
}

private func terminalBundleInfo(
    displayName: String = "Mock Terminal",
    bundleName: String = "Mock Terminal",
    documentTypes: Any
) -> [String: Any] {
    [
        "CFBundleDisplayName": displayName,
        "CFBundleName": bundleName,
        "CFBundleIdentifier": "dev.finallyexplorer.mock-terminal",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleExecutable": "MockTerminal",
        "CFBundleDocumentTypes": documentTypes
    ]
}

private func makeTerminalApplicationBundle(
    info: [String: Any]? = nil,
    infoData: Data? = nil
) throws -> URL {
    let applicationURL = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorer-Terminal-Bundle-\(UUID().uuidString).app",
        directoryHint: .isDirectory
    )
    let contentsURL = applicationURL.appending(path: "Contents", directoryHint: .isDirectory)
    let executableDirectoryURL = contentsURL.appending(
        path: "MacOS",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: executableDirectoryURL,
        withIntermediateDirectories: true
    )

    let plistData: Data
    if let infoData {
        plistData = infoData
    } else {
        plistData = try PropertyListSerialization.data(
            fromPropertyList: info ?? terminalBundleInfo(
                documentTypes: [["CFBundleTypeRole": "Shell"]]
            ),
            format: .xml,
            options: 0
        )
    }
    try plistData.write(to: contentsURL.appending(path: "Info.plist"))
    try Data().write(to: executableDirectoryURL.appending(path: "MockTerminal"))

    return applicationURL
}
