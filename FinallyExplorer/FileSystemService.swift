//
//  FileSystemService.swift
//  FinallyExplorer
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum DirectoryAccessError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case permissionDenied(path: String, folderTitle: String)
    case notFound(path: String, folderTitle: String)
    case notDirectory(path: String, folderTitle: String)
    case corrupt(path: String)
    case sizeOverflow(path: String)
    case unknown(message: String, path: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid directory URL"
        case let .permissionDenied(path, folderTitle):
            "Permission denied. Please check System Settings > Privacy & Security > Files and Folders to grant access to the \(folderTitle) folder.\n\nPath: \(path)"
        case let .notFound(path, folderTitle):
            "The \(folderTitle) folder could not be found at this location.\n\nPath: \(path)"
        case let .notDirectory(path, folderTitle):
            "The \(folderTitle) location is not a folder.\n\nPath: \(path)"
        case let .corrupt(path):
            "Unable to read the folder. It may be corrupted or inaccessible.\n\nPath: \(path)"
        case let .sizeOverflow(path):
            "The folder is too large to represent its size.\n\nPath: \(path)"
        case let .unknown(message, path):
            "Unable to access folder: \(message)\n\nPath: \(path)"
        }
    }
}

nonisolated struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isImage: Bool
    let fileSize: Int64?
    let modificationDate: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    static func displayOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }

        // Case-sensitive volumes can contain names whose localized,
        // case-insensitive forms compare equally. A scalar-order tiebreaker
        // keeps the UI stable instead of inheriting filesystem enumeration order.
        return lhs.name < rhs.name
    }
}

nonisolated struct DirectoryNavigationState: Equatable, Sendable {
    private(set) var path: [URL] = []

    var currentDirectory: URL? { path.last }
    var canGoBack: Bool { path.isEmpty == false }

    mutating func open(_ url: URL) {
        guard url != currentDirectory else { return }
        path.append(url)
    }

    mutating func goBack() {
        guard path.isEmpty == false else { return }
        path.removeLast()
    }
}

nonisolated struct FileSystemService: Sendable {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .contentTypeKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    private static let sizeResourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .fileSizeKey,
    ]

    @concurrent
    func contents(of url: URL, folderTitle: String) async throws -> [FileItem] {
        try Task.checkCancellation()
        guard Self.isLocalFileURL(url) else {
            throw DirectoryAccessError.invalidURL
        }

        let resolvedURL = url.resolvingSymlinksInPath()
        let contents: [URL]

        do {
            let rootValues = try resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard rootValues.isDirectory == true else {
                throw DirectoryAccessError.notDirectory(
                    path: resolvedURL.path,
                    folderTitle: folderTitle
                )
            }

            contents = try FileManager.default.contentsOfDirectory(
                at: resolvedURL,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch let error as DirectoryAccessError {
            throw error
        } catch let error as CocoaError {
            throw Self.directoryAccessError(
                from: error,
                path: resolvedURL.path,
                folderTitle: folderTitle
            )
        } catch {
            throw DirectoryAccessError.unknown(
                message: error.localizedDescription,
                path: resolvedURL.path
            )
        }

        var items: [FileItem] = []
        items.reserveCapacity(contents.count)

        for url in contents {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: Self.resourceKeys)
            let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)

            items.append(
                FileItem(
                    url: url,
                    isDirectory: values?.isDirectory ?? false,
                    isImage: contentType?.conforms(to: .image) == true,
                    fileSize: values?.fileSize.map(Int64.init),
                    modificationDate: values?.contentModificationDate
                )
            )
        }

        try Task.checkCancellation()
        return items.sorted(by: FileItem.displayOrder)
    }

    @concurrent
    func size(of url: URL) async throws -> Int64 {
        try Task.checkCancellation()
        guard Self.isLocalFileURL(url) else {
            throw DirectoryAccessError.invalidURL
        }

        let resolvedURL = url.resolvingSymlinksInPath()
        let folderTitle = resolvedURL.lastPathComponent.isEmpty
            ? "Folder"
            : resolvedURL.lastPathComponent
        let rootValues: URLResourceValues

        do {
            rootValues = try resolvedURL.resourceValues(forKeys: Self.sizeResourceKeys)
        } catch let error as CocoaError {
            throw Self.directoryAccessError(
                from: error,
                path: resolvedURL.path,
                folderTitle: folderTitle
            )
        } catch {
            throw DirectoryAccessError.unknown(
                message: error.localizedDescription,
                path: resolvedURL.path
            )
        }

        guard rootValues.isDirectory == true else {
            return rootValues.fileSize.map(Int64.init) ?? 0
        }

        var enumerationFailure: DirectoryAccessError?

        guard let enumerator = FileManager.default.enumerator(
            at: resolvedURL,
            includingPropertiesForKeys: Array(Self.sizeResourceKeys),
            options: [],
            errorHandler: { failingURL, error in
                if enumerationFailure == nil {
                    if let cocoaError = error as? CocoaError {
                        enumerationFailure = Self.directoryAccessError(
                            from: cocoaError,
                            path: failingURL.path,
                            folderTitle: folderTitle
                        )
                    } else {
                        enumerationFailure = .unknown(
                            message: error.localizedDescription,
                            path: failingURL.path
                        )
                    }
                }
                return false
            }
        ) else {
            throw DirectoryAccessError.unknown(
                message: "Unable to enumerate folder contents.",
                path: resolvedURL.path
            )
        }

        var totalSize: Int64 = 0

        while let childURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            if let enumerationFailure {
                throw enumerationFailure
            }

            guard let values = try? childURL.resourceValues(forKeys: Self.sizeResourceKeys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }

            totalSize = try Self.addingFileSize(
                Int64(fileSize),
                to: totalSize,
                path: resolvedURL.path
            )
        }

        try Task.checkCancellation()

        if let enumerationFailure {
            throw enumerationFailure
        }

        return totalSize
    }

    static func addingFileSize(
        _ fileSize: Int64,
        to totalSize: Int64,
        path: String
    ) throws -> Int64 {
        guard fileSize >= 0 else {
            throw DirectoryAccessError.corrupt(path: path)
        }

        let (newTotal, overflowed) = totalSize.addingReportingOverflow(fileSize)
        guard overflowed == false else {
            throw DirectoryAccessError.sizeOverflow(path: path)
        }

        return newTotal
    }

    private static func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        guard let host = url.host(percentEncoded: false), host.isEmpty == false else {
            return true
        }

        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    private static func directoryAccessError(
        from error: CocoaError,
        path: String,
        folderTitle: String
    ) -> DirectoryAccessError {
        switch error.code {
        case .fileReadNoPermission:
            .permissionDenied(path: path, folderTitle: folderTitle)
        case .fileReadNoSuchFile:
            .notFound(path: path, folderTitle: folderTitle)
        case .fileReadCorruptFile:
            .corrupt(path: path)
        default:
            .unknown(message: error.localizedDescription, path: path)
        }
    }
}
