//
//  FileRenameTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct FileRenameTests {
    @Test("A file rename preserves its bytes and changes only its directory entry")
    func renamesFileWithoutChangingContents() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Before.txt")
        let expectedData = Data("unchanged".utf8)
        try expectedData.write(to: sourceURL)

        let outcome = try await FileOperationService().renameItem(
            at: sourceURL,
            to: "After.txt"
        )

        #expect(outcome.didChange)
        #expect(outcome.destinationURL.lastPathComponent == "After.txt")
        #expect(try Data(contentsOf: outcome.destinationURL) == expectedData)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
    }

    @Test("A folder rename preserves descendants")
    func renamesFolderWithDescendants() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Before", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: false)
        try Data("child".utf8).write(to: sourceURL.appending(path: "child.txt"))

        let outcome = try await FileOperationService().renameItem(
            at: sourceURL,
            to: "After"
        )

        #expect(outcome.didChange)
        #expect(try Data(contentsOf: outcome.destinationURL.appending(path: "child.txt")) == Data("child".utf8))
    }

    @Test("Rename never overwrites an existing sibling")
    func renameCollisionPreservesBothItems() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Source.txt")
        let destinationURL = root.appending(path: "Destination.txt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("destination".utf8).write(to: destinationURL)

        await #expect(
            throws: FileOperationError.destinationAlreadyExists(
                path: destinationURL.path
            )
        ) {
            try await FileOperationService().renameItem(
                at: sourceURL,
                to: destinationURL.lastPathComponent
            )
        }

        #expect(try Data(contentsOf: sourceURL) == Data("source".utf8))
        #expect(try Data(contentsOf: destinationURL) == Data("destination".utf8))
    }

    @Test("Case-only rename works on both case-sensitive and insensitive volumes")
    func caseOnlyRename() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Report.txt")
        try Data("report".utf8).write(to: sourceURL)

        let outcome = try await FileOperationService().renameItem(
            at: sourceURL,
            to: "report.TXT"
        )
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)

        #expect(outcome.didChange)
        #expect(names == ["report.TXT"])
        #expect(try Data(contentsOf: outcome.destinationURL) == Data("report".utf8))
    }

    @Test("Submitting the existing name is a no-op")
    func existingNameDoesNothing() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Same.txt")
        try Data("same".utf8).write(to: sourceURL)

        let outcome = try await FileOperationService().renameItem(
            at: sourceURL,
            to: sourceURL.lastPathComponent
        )

        #expect(outcome == FileOperationOutcome(destinationURL: sourceURL, didChange: false))
    }

    @Test("Malformed file names are rejected before touching the source")
    func rejectsMalformedNames() async throws {
        let root = try makeRenameTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "Safe.txt")
        try Data("safe".utf8).write(to: sourceURL)
        let invalidNames = [
            "",
            "   ",
            ".",
            "..",
            "folder/name",
            "legacy:name",
            "null\0name",
            String(repeating: "é", count: 128),
        ]

        for invalidName in invalidNames {
            do {
                _ = try await FileOperationService().renameItem(
                    at: sourceURL,
                    to: invalidName
                )
                Issue.record("Expected invalid name to be rejected: \(invalidName.debugDescription)")
            } catch FileOperationError.invalidName {
                // Expected.
            } catch {
                Issue.record("Unexpected error for \(invalidName.debugDescription): \(error)")
            }
        }

        #expect(try Data(contentsOf: sourceURL) == Data("safe".utf8))
    }

    @Test("The file-system root cannot be renamed")
    func rejectsFileSystemRoot() async {
        await #expect(throws: FileOperationError.cannotRenameFileSystemRoot) {
            try await FileOperationService().renameItem(
                at: URL(filePath: "/", directoryHint: .isDirectory),
                to: "renamed-root"
            )
        }
    }

    @Test("URL relocation changes only the renamed item and its descendants")
    func relocatesMatchingURLsOnly() throws {
        let source = URL(filePath: "/tmp/Before", directoryHint: .isDirectory)
        let destination = URL(filePath: "/tmp/After", directoryHint: .isDirectory)
        let child = source.appending(path: "Nested/file.txt")

        #expect(
            FileURLRelocation.rebase(child, from: source, to: destination)
                == destination.appending(path: "Nested/file.txt")
        )
        #expect(
            FileURLRelocation.rebase(
                URL(filePath: "/tmp/Before-Similar/file.txt"),
                from: source,
                to: destination
            ) == nil
        )
    }

    @Test("Renaming a favorited folder keeps sidebar and pane references valid")
    @MainActor
    func rebasesSidebarAndWorkspaceReferences() throws {
        let source = URL(filePath: "/tmp/Before", directoryHint: .isDirectory)
        let destination = URL(filePath: "/tmp/After", directoryHint: .isDirectory)
        let favorite = SidebarFavorite(directoryURL: source)
        let store = RenameSidebarStore(favorites: [favorite])
        let monitor = MountedVolumeMonitor(
            loadVolumes: { [] },
            observesWorkspaceChanges: false
        )
        let sidebar = SidebarModel(store: store, mountedVolumeMonitor: monitor)
        let workspace = WorkspaceModel(initialPlace: .favorite(favorite))
        let pane = try #require(workspace.activePane)
        let selectedChild = source.appending(path: "Nested/file.txt")
        pane.navigation.open(source.appending(path: "Nested", directoryHint: .isDirectory))
        pane.selectedURL = selectedChild
        let result = FileRenameResult(
            sourceURL: source,
            destinationURL: destination
        )

        sidebar.applyRename(result)
        workspace.applyRename(result)

        #expect(sidebar.favorites.first?.directoryURL == destination)
        #expect(sidebar.favorites.first?.title == "After")
        #expect(store.savedFavorites.last?.directoryURL == destination)
        #expect(pane.place.url == destination)
        #expect(
            pane.navigation.currentDirectory
                == destination.appending(path: "Nested", directoryHint: .isDirectory)
        )
        #expect(pane.selectedURL == destination.appending(path: "Nested/file.txt"))
        #expect(
            pane.pendingRevealURL
                == destination.appending(path: "Nested/file.txt")
        )
    }

    private func makeRenameTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "FinallyExplorerRenameTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        return root
    }
}

@MainActor
private final class RenameSidebarStore: SidebarFavoriteStoring {
    let favorites: [SidebarFavorite]
    private(set) var savedFavorites: [SidebarFavorite] = []

    init(favorites: [SidebarFavorite]) {
        self.favorites = favorites
    }

    func loadFavorites() -> [SidebarFavorite] { favorites }

    func saveFavorites(_ favorites: [SidebarFavorite]) {
        savedFavorites = favorites
    }
}
