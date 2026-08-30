//
//  FinallyExplorerTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct FileSystemServiceTests {
    @Test("Directories are listed before files and each group is sorted by name")
    func directoryContentsUseDisplayOrder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "b-folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "a-folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try Data("B".utf8).write(to: root.appending(path: "b.txt"))
        try Data("A".utf8).write(to: root.appending(path: "a.txt"))

        let items = try await FileSystemService().contents(of: root, folderTitle: "Test")

        #expect(items.map(\.name) == ["a-folder", "b-folder", "a.txt", "b.txt"])
        #expect(items.map(\.isDirectory) == [true, true, false, false])
    }

    @Test("File metadata is returned with the directory contents")
    func fileMetadataIsLoaded() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = Data("Finally Explorer".utf8)
        try data.write(to: root.appending(path: "note.txt"))

        let items = try await FileSystemService().contents(of: root, folderTitle: "Test")
        let item = try #require(items.first)

        #expect(item.name == "note.txt")
        #expect(item.isDirectory == false)
        #expect(item.isImage == false)
        #expect(item.fileSize == Int64(data.count))
        #expect(item.modificationDate != nil)
    }

    @Test("Image files are identified from their content type")
    func imageFilesAreIdentified() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appending(path: "preview.png"))

        let items = try await FileSystemService().contents(of: root, folderTitle: "Test")
        let image = try #require(items.first)

        #expect(image.name == "preview.png")
        #expect(image.isImage)
    }

    @Test("Hidden items are excluded by default and opt in with metadata")
    func hiddenFilesAreSkipped() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appending(path: ".hidden"))
        try FileManager.default.createDirectory(
            at: root.appending(path: ".hidden-folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try Data().write(to: root.appending(path: "visible.txt"))

        let defaultItems = try await FileSystemService().contents(
            of: root,
            folderTitle: "Test"
        )
        let allItems = try await FileSystemService().contents(
            of: root,
            folderTitle: "Test",
            includingHiddenItems: true
        )

        #expect(defaultItems.map(\.name) == ["visible.txt"])
        #expect(allItems.map(\.name) == [".hidden-folder", ".hidden", "visible.txt"])
        #expect(allItems.filter(\.isHidden).map(\.name) == [".hidden-folder", ".hidden"])
    }

    @Test("Folder size includes files in nested folders")
    func recursiveFolderSizeIsCalculated() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nestedFolder = root.appending(path: "nested", directoryHint: .isDirectory)
        let emptyFolder = root.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: nestedFolder,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: emptyFolder,
            withIntermediateDirectories: false
        )

        let rootFile = Data(repeating: 0xA5, count: 11)
        let nestedFile = Data(repeating: 0x5A, count: 17)
        let rootFileURL = root.appending(path: "root.bin")
        try rootFile.write(to: rootFileURL)
        try nestedFile.write(to: nestedFolder.appending(path: "nested.bin"))

        let service = FileSystemService()
        let folderSize = try await service.size(of: root)
        let fileSize = try await service.size(of: rootFileURL)
        let emptyFolderSize = try await service.size(of: emptyFolder)

        #expect(folderSize == Int64(rootFile.count + nestedFile.count))
        #expect(fileSize == Int64(rootFile.count))
        #expect(emptyFolderSize == 0)
    }

    @Test("Missing paths map to one domain error for listing and sizing")
    func missingPathMapsToNotFound() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "FinallyExplorerTests-missing-\(UUID().uuidString)")
        let resolvedURL = missingURL.resolvingSymlinksInPath()
        let expectedError = DirectoryAccessError.notFound(
            path: resolvedURL.path,
            folderTitle: resolvedURL.lastPathComponent
        )

        await #expect(throws: expectedError) {
            try await FileSystemService().contents(
                of: missingURL,
                folderTitle: resolvedURL.lastPathComponent
            )
        }
        await #expect(throws: expectedError) {
            try await FileSystemService().size(of: missingURL)
        }
    }

    @Test("Non-local URLs are rejected before their path can alias a local folder")
    func nonLocalURLsAreRejected() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let remoteURL = try #require(URL(string: "https://example.com/not-a-local-folder"))
        let remoteHostFileURL = try #require(
            URL(string: "file://example.com\(root.path(percentEncoded: true))")
        )
        let localhostFileURL = try #require(
            URL(string: "file://localhost\(root.path(percentEncoded: true))")
        )
        let service = FileSystemService()

        for invalidURL in [remoteURL, remoteHostFileURL] {
            await #expect(throws: DirectoryAccessError.invalidURL) {
                try await service.contents(of: invalidURL, folderTitle: "Remote")
            }
            await #expect(throws: DirectoryAccessError.invalidURL) {
                try await service.size(of: invalidURL)
            }
        }

        let localhostContents = try await service.contents(
            of: localhostFileURL,
            folderTitle: "Localhost"
        )
        let localhostSize = try await service.size(of: localhostFileURL)

        #expect(localhostContents.isEmpty)
        #expect(localhostSize == 0)
    }

    @Test("A file cannot be listed as though it were a directory")
    func filePassedToDirectoryListingIsRejected() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appending(path: "ordinary.txt")
        try Data("not a directory".utf8).write(to: fileURL)
        let expectedPath = fileURL.resolvingSymlinksInPath().path

        await #expect(
            throws: DirectoryAccessError.notDirectory(
                path: expectedPath,
                folderTitle: "Ordinary"
            )
        ) {
            try await FileSystemService().contents(
                of: fileURL,
                folderTitle: "Ordinary"
            )
        }
    }

    @Test("Listing and sizing observe cancellation before touching the filesystem")
    func entryPointsObservePreexistingCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let contentsTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileSystemService().contents(of: root, folderTitle: "Test")
        }
        let sizeTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileSystemService().size(of: root)
        }

        await #expect(throws: CancellationError.self) {
            try await contentsTask.value
        }
        await #expect(throws: CancellationError.self) {
            try await sizeTask.value
        }
    }

    @Test("Folder sizing stops at symbolic-link cycles and counts each real file once")
    func symbolicLinkCycleDoesNotRecurse() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: false
        )
        let payload = Data(repeating: 0xAB, count: 31)
        try payload.write(to: nested.appending(path: "payload.bin"))
        try FileManager.default.createSymbolicLink(
            at: nested.appending(path: "back-to-root"),
            withDestinationURL: root
        )

        let size = try await FileSystemService().size(of: root)

        #expect(size == Int64(payload.count))
    }

    @Test("An unreadable descendant fails sizing instead of returning a partial total")
    func unreadableDescendantDoesNotProducePartialSize() async throws {
        let root = try makeTemporaryDirectory()
        let protectedFolder = root.appending(
            path: "protected",
            directoryHint: .isDirectory
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: protectedFolder.path
            )
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: protectedFolder,
            withIntermediateDirectories: false
        )
        try Data(repeating: 0xCD, count: 19).write(
            to: protectedFolder.appending(path: "unreadable.bin")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: protectedFolder.path
        )

        let resolvedRoot = root.resolvingSymlinksInPath()
        do {
            _ = try await FileSystemService().size(of: root)
            Issue.record("Expected the unreadable descendant to fail folder sizing.")
        } catch let DirectoryAccessError.permissionDenied(path, folderTitle) {
            let failedURL = URL(filePath: path)
            #expect(failedURL.lastPathComponent == "protected")
            #expect(
                failedURL.deletingLastPathComponent().lastPathComponent
                    == resolvedRoot.lastPathComponent
            )
            #expect(folderTitle == resolvedRoot.lastPathComponent)
        } catch {
            Issue.record("Expected permissionDenied, received \(error).")
        }
    }

    @Test("A bounded high-cardinality tree is sized without dropping entries")
    func highCardinalityTreeHasExactSize() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var expectedSize: Int64 = 0
        for directoryIndex in 0..<16 {
            let directory = root.appending(
                path: "directory-\(directoryIndex)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )

            for fileIndex in 0..<64 {
                let byteCount = (directoryIndex + fileIndex) % 23
                try Data(repeating: UInt8(fileIndex), count: byteCount).write(
                    to: directory.appending(path: "file-\(fileIndex).bin")
                )
                expectedSize += Int64(byteCount)
            }
        }

        let service = FileSystemService()
        let contents = try await service.contents(of: root, folderTitle: "Stress")
        let size = try await service.size(of: root)

        #expect(contents.count == 16)
        #expect(contents.allSatisfy { $0.isDirectory })
        #expect(size == expectedSize)
    }

    @Test("Size accumulation accepts the Int64 boundary and rejects corruption or overflow")
    func fileSizeAccumulationChecksBoundaries() throws {
        let path = "/test/boundary"

        #expect(
            try FileSystemService.addingFileSize(
                Int64.max - 1,
                to: 1,
                path: path
            ) == Int64.max
        )
        #expect(throws: DirectoryAccessError.sizeOverflow(path: path)) {
            try FileSystemService.addingFileSize(1, to: Int64.max, path: path)
        }
        #expect(throws: DirectoryAccessError.corrupt(path: path)) {
            try FileSystemService.addingFileSize(-1, to: 0, path: path)
        }
    }

    @Test("Case-insensitive name ties have a deterministic scalar-order fallback")
    func displayOrderBreaksCaseInsensitiveTies() {
        let root = URL(filePath: "/test", directoryHint: .isDirectory)
        let items = ["a", "A"].map { name in
            FileItem(
                url: root.appending(path: name),
                isDirectory: false,
                isImage: false,
                fileSize: nil,
                modificationDate: nil
            )
        }

        #expect(items.sorted(by: FileItem.displayOrder).map(\.name) == ["A", "a"])
    }
}

struct DirectoryNavigationStateTests {
    @Test("Opening folders and going back maintains one navigation path")
    func navigationPathMovesBackOneLevelAtATime() {
        let first = URL(filePath: "/tmp/first", directoryHint: .isDirectory)
        let second = first.appending(path: "second", directoryHint: .isDirectory)
        var navigation = DirectoryNavigationState()

        #expect(navigation.currentDirectory == nil)
        #expect(navigation.canGoBack == false)

        navigation.open(first)
        navigation.open(second)
        #expect(navigation.currentDirectory == second)
        #expect(navigation.canGoBack)

        navigation.goBack()
        #expect(navigation.currentDirectory == first)

        navigation.goBack()
        navigation.goBack()
        #expect(navigation.currentDirectory == nil)
        #expect(navigation.canGoBack == false)
    }

    @Test("Opening the current folder twice does not corrupt back navigation")
    func duplicateCurrentDirectoryIsIgnored() {
        let folder = URL(filePath: "/tmp/folder", directoryHint: .isDirectory)
        var navigation = DirectoryNavigationState()

        navigation.open(folder)
        navigation.open(folder)
        navigation.goBack()

        #expect(navigation.currentDirectory == nil)
        #expect(navigation.canGoBack == false)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "FinallyExplorerTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
