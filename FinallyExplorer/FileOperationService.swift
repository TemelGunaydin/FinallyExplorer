//
//  FileOperationService.swift
//  FinallyExplorer
//

import Darwin
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A private-to-Finally-Explorer drag payload.
    ///
    /// The app intentionally does not advertise `public.file-url` or a file
    /// representation, so this payload cannot be used to export items to Finder.
    nonisolated static let finallyExplorerInternalFileTransfer = UTType(
        exportedAs: "com.temelgunaydin.finallyexplorer.internal-file-transfer",
        conformingTo: .data
    )
}

/// The in-memory payload resolved from an opaque, process-local drag token.
nonisolated struct InternalFileTransfer: Hashable, Identifiable, Sendable {
    nonisolated struct ID: Hashable, Sendable {
        let sourceURL: URL
        let sourcePaneID: UUID
    }

    let sourceURL: URL
    let sourcePaneID: UUID

    var id: ID {
        ID(sourceURL: sourceURL, sourcePaneID: sourcePaneID)
    }

}

/// Resolves the Finder-style operation for an internal drop.
///
/// Moving inside one pane keeps the existing behavior. Crossing a pane boundary
/// copies the item so both folder views remain intact. Unknown or mixed drag
/// identities deliberately fall back to copying, which is the safer operation.
nonisolated enum InternalFileDropAction: Equatable, Sendable {
    case copy
    case move

    init(sourcePaneIDs: [UUID], destinationPaneID: UUID) {
        self = sourcePaneIDs.isEmpty == false
            && sourcePaneIDs.allSatisfy { $0 == destinationPaneID }
            ? .move
            : .copy
    }
}

nonisolated struct FileOperationOutcome: Equatable, Sendable {
    let destinationURL: URL
    let didChange: Bool
}

nonisolated protocol FileOperationServicing: Sendable {
    func createFolder(in destinationDirectoryURL: URL) async throws -> FileOperationOutcome
    func setHidden(_ hidden: Bool, for directoryURL: URL) async throws -> FileOperationOutcome
    func copyItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome
    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome
}

nonisolated enum FileOperationError: LocalizedError, Equatable, Sendable {
    case sourceMustBeFileURL(value: String)
    case destinationMustBeFileURL(value: String)
    case sourceNotFound(path: String)
    case destinationNotFound(path: String)
    case destinationIsNotDirectory(path: String)
    case destinationAlreadyExists(path: String)
    case cannotPlaceDirectoryInsideItself(sourcePath: String, destinationPath: String)
    case sourceIsNotDirectory(path: String)
    case cannotUnhideDotPrefixedDirectory(path: String)
    case visibilityChangeFailed(path: String, hidden: Bool, reason: String)
    case createFolderFailed(destinationPath: String, reason: String)
    case copyFailed(sourcePath: String, destinationPath: String, reason: String)
    case moveFailed(sourcePath: String, destinationPath: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .sourceMustBeFileURL(value):
            "The item to be copied or moved is not a local file URL.\n\nValue: \(value)"
        case let .destinationMustBeFileURL(value):
            "The destination is not a local file URL.\n\nValue: \(value)"
        case let .sourceNotFound(path):
            "The item to be copied or moved could not be found.\n\nPath: \(path)"
        case let .destinationNotFound(path):
            "The destination folder could not be found.\n\nPath: \(path)"
        case let .destinationIsNotDirectory(path):
            "The destination must be a folder.\n\nPath: \(path)"
        case let .destinationAlreadyExists(path):
            "An item with the same name already exists in the destination folder.\n\nPath: \(path)"
        case let .cannotPlaceDirectoryInsideItself(sourcePath, destinationPath):
            "A folder cannot be copied or moved into itself or one of its subfolders.\n\nSource: \(sourcePath)\nDestination: \(destinationPath)"
        case let .sourceIsNotDirectory(path):
            "Only folders can be hidden with this command.\n\nPath: \(path)"
        case let .cannotUnhideDotPrefixedDirectory(path):
            "This folder stays hidden because its name begins with a period. Rename it before turning off its hidden status.\n\nPath: \(path)"
        case let .visibilityChangeFailed(path, hidden, reason):
            "Unable to \(hidden ? "hide" : "unhide") the folder: \(reason)\n\nPath: \(path)"
        case let .createFolderFailed(destinationPath, reason):
            "Unable to create the folder: \(reason)\n\nPath: \(destinationPath)"
        case let .copyFailed(sourcePath, destinationPath, reason):
            "Unable to copy the item: \(reason)\n\nSource: \(sourcePath)\nDestination: \(destinationPath)"
        case let .moveFailed(sourcePath, destinationPath, reason):
            "Unable to move the item: \(reason)\n\nSource: \(sourcePath)\nDestination: \(destinationPath)"
        }
    }
}

/// Performs non-destructive file operations away from the caller's executor.
nonisolated struct FileOperationService: FileOperationServicing, Sendable {
    /// Changes a folder's Finder-compatible hidden resource flag.
    @concurrent
    func setHidden(
        _ hidden: Bool,
        for directoryURL: URL
    ) async throws -> FileOperationOutcome {
        try Task.checkCancellation()
        guard Self.isLocalFileURL(directoryURL) else {
            throw FileOperationError.sourceMustBeFileURL(
                value: directoryURL.absoluteString
            )
        }

        var directoryURL = directoryURL.standardizedFileURL
        let fileManager = FileManager()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ) else {
            throw FileOperationError.sourceNotFound(path: directoryURL.path)
        }
        guard isDirectory.boolValue else {
            throw FileOperationError.sourceIsNotDirectory(path: directoryURL.path)
        }
        if hidden == false, directoryURL.lastPathComponent.hasPrefix(".") {
            throw FileOperationError.cannotUnhideDotPrefixedDirectory(
                path: directoryURL.path
            )
        }

        let currentValues: URLResourceValues
        do {
            currentValues = try directoryURL.resourceValues(forKeys: [.isHiddenKey])
        } catch {
            throw FileOperationError.visibilityChangeFailed(
                path: directoryURL.path,
                hidden: hidden,
                reason: error.localizedDescription
            )
        }

        guard currentValues.isHidden != hidden else {
            return FileOperationOutcome(
                destinationURL: directoryURL,
                didChange: false
            )
        }

        try Task.checkCancellation()
        var updatedValues = URLResourceValues()
        updatedValues.isHidden = hidden

        do {
            try directoryURL.setResourceValues(updatedValues)
            let verifiedValues = try directoryURL.resourceValues(
                forKeys: [.isHiddenKey]
            )
            guard verifiedValues.isHidden == hidden else {
                throw FileOperationError.visibilityChangeFailed(
                    path: directoryURL.path,
                    hidden: hidden,
                    reason: "The file system did not preserve the requested setting."
                )
            }
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw FileOperationError.visibilityChangeFailed(
                path: directoryURL.path,
                hidden: hidden,
                reason: error.localizedDescription
            )
        }

        return FileOperationOutcome(
            destinationURL: directoryURL,
            didChange: true
        )
    }

    /// Creates a uniquely named folder without overwriting an existing item.
    ///
    /// The first folder is named `New Folder`, followed by `New Folder 2`,
    /// `New Folder 3`, and so on when a name is already occupied.
    @concurrent
    func createFolder(
        in destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        try Task.checkCancellation()

        let fileManager = FileManager()
        let destinationDirectoryURL = try Self.validatedDestinationDirectory(
            destinationDirectoryURL,
            fileManager: fileManager
        )
        var folderNumber = 1

        while true {
            try Task.checkCancellation()

            let folderName = folderNumber == 1
                ? "New Folder"
                : "New Folder \(folderNumber)"
            let folderURL = destinationDirectoryURL.appending(
                path: folderName,
                directoryHint: .isDirectory
            )

            guard Self.itemExists(at: folderURL, fileManager: fileManager) == false else {
                folderNumber += 1
                continue
            }

            try Task.checkCancellation()

            do {
                try fileManager.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: false
                )
            } catch {
                // Another process may have claimed this name after our check.
                // In that case, continue the Finder-style numbering sequence.
                if Self.itemExists(at: folderURL, fileManager: fileManager) {
                    folderNumber += 1
                    continue
                }

                throw FileOperationError.createFolderFailed(
                    destinationPath: folderURL.path,
                    reason: error.localizedDescription
                )
            }

            return FileOperationOutcome(destinationURL: folderURL, didChange: true)
        }
    }

    /// Copies an item into `destinationDirectoryURL` without overwriting anything.
    ///
    /// When the original name is occupied, this creates `name copy`, then
    /// `name copy 2`, and so on. File extensions remain at the end of the name.
    @concurrent
    func copyItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        try Task.checkCancellation()

        let fileManager = FileManager()
        let operation = try Self.validatedOperation(
            sourceURL: sourceURL,
            destinationDirectoryURL: destinationDirectoryURL,
            fileManager: fileManager
        )
        var destinationURL = try Self.uniqueCopyDestination(
            for: operation.sourceURL,
            in: operation.destinationDirectoryURL,
            sourceIsDirectory: operation.sourceIsDirectory,
            fileManager: fileManager
        )
        let stagingURL = Self.uniqueCopyStagingURL(
            in: operation.destinationDirectoryURL,
            fileManager: fileManager
        )

        try Task.checkCancellation()

        do {
            try fileManager.copyItem(at: operation.sourceURL, to: stagingURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw FileOperationError.copyFailed(
                sourcePath: operation.sourceURL.path,
                destinationPath: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            // FileManager's copy operation is synchronous and cannot be interrupted.
            // Observe cancellation before exposing the completely staged result.
            try Task.checkCancellation()

            while true {
                do {
                    try Self.moveItemExclusively(
                        at: stagingURL,
                        to: destinationURL
                    )
                    break
                } catch {
                    guard Self.isDestinationCollision(error) else {
                        throw error
                    }

                    // Another process may have claimed the candidate between name
                    // selection and the atomic move. Reuse the completed staging
                    // copy and select the next available Finder-style name.
                    destinationURL = try Self.uniqueCopyDestination(
                        for: operation.sourceURL,
                        in: operation.destinationDirectoryURL,
                        sourceIsDirectory: operation.sourceIsDirectory,
                        fileManager: fileManager
                    )
                    try Task.checkCancellation()
                }
            }
        } catch is CancellationError {
            try? fileManager.removeItem(at: stagingURL)
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw FileOperationError.copyFailed(
                sourcePath: operation.sourceURL.path,
                destinationPath: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        return FileOperationOutcome(destinationURL: destinationURL, didChange: true)
    }

    /// Moves an item into `destinationDirectoryURL` without overwriting anything.
    ///
    /// Moving an item to the folder it already belongs to is a successful no-op.
    @concurrent
    func moveItem(
        at sourceURL: URL,
        to destinationDirectoryURL: URL
    ) async throws -> FileOperationOutcome {
        try Task.checkCancellation()

        let fileManager = FileManager()
        let operation = try Self.validatedOperation(
            sourceURL: sourceURL,
            destinationDirectoryURL: destinationDirectoryURL,
            fileManager: fileManager
        )
        let sourceParentURL = operation.sourceURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL

        if sourceParentURL == operation.destinationDirectoryURL {
            try Task.checkCancellation()
            return FileOperationOutcome(
                destinationURL: operation.sourceURL,
                didChange: false
            )
        }

        let destinationURL = operation.destinationDirectoryURL.appending(
            path: operation.sourceURL.lastPathComponent,
            directoryHint: operation.sourceIsDirectory ? .isDirectory : .notDirectory
        )

        guard Self.itemExists(at: destinationURL, fileManager: fileManager) == false else {
            throw FileOperationError.destinationAlreadyExists(path: destinationURL.path)
        }

        try Task.checkCancellation()

        do {
            do {
                try Self.moveItemExclusively(
                    at: operation.sourceURL,
                    to: destinationURL
                )
            } catch let error as NSError where Self.isCrossDeviceMove(error) {
                try Self.moveAcrossVolumes(
                    sourceURL: operation.sourceURL,
                    destinationURL: destinationURL,
                    destinationDirectoryURL: operation.destinationDirectoryURL,
                    fileManager: fileManager
                )
            }
        } catch let error where Self.isDestinationCollision(error) {
            throw FileOperationError.destinationAlreadyExists(path: destinationURL.path)
        } catch {
            throw FileOperationError.moveFailed(
                sourcePath: operation.sourceURL.path,
                destinationPath: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        return FileOperationOutcome(destinationURL: destinationURL, didChange: true)
    }

    private struct ValidatedOperation {
        let sourceURL: URL
        let destinationDirectoryURL: URL
        let sourceIsDirectory: Bool
    }

    private static func validatedOperation(
        sourceURL: URL,
        destinationDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> ValidatedOperation {
        guard Self.isLocalFileURL(sourceURL) else {
            throw FileOperationError.sourceMustBeFileURL(value: sourceURL.absoluteString)
        }

        guard Self.isLocalFileURL(destinationDirectoryURL) else {
            throw FileOperationError.destinationMustBeFileURL(
                value: destinationDirectoryURL.absoluteString
            )
        }

        let sourceURL = sourceURL.standardizedFileURL
        let destinationDirectoryURL = destinationDirectoryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard let sourceAttributes = try? fileManager.attributesOfItem(
            atPath: sourceURL.path
        ) else {
            throw FileOperationError.sourceNotFound(path: sourceURL.path)
        }
        let sourceType = sourceAttributes[.type] as? FileAttributeType
        let sourceIsDirectory = sourceType == .typeDirectory
        let sourceIsSymbolicLink = sourceType == .typeSymbolicLink

        var destinationIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: destinationDirectoryURL.path,
            isDirectory: &destinationIsDirectory
        ) else {
            throw FileOperationError.destinationNotFound(path: destinationDirectoryURL.path)
        }

        guard destinationIsDirectory.boolValue else {
            throw FileOperationError.destinationIsNotDirectory(
                path: destinationDirectoryURL.path
            )
        }

        let isRealDirectory = sourceIsDirectory && sourceIsSymbolicLink == false

        if isRealDirectory {
            let resolvedSourceURL = sourceURL
                .resolvingSymlinksInPath()
                .standardizedFileURL

            if destinationDirectoryURL == resolvedSourceURL
                || Self.isDescendant(
                    destinationDirectoryURL,
                    of: resolvedSourceURL
                ) {
                throw FileOperationError.cannotPlaceDirectoryInsideItself(
                    sourcePath: sourceURL.path,
                    destinationPath: destinationDirectoryURL.path
                )
            }
        }

        return ValidatedOperation(
            sourceURL: sourceURL,
            destinationDirectoryURL: destinationDirectoryURL,
            sourceIsDirectory: sourceIsDirectory
        )
    }

    private static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let ancestorComponents = ancestor.pathComponents
        let candidateComponents = candidate.pathComponents

        guard candidateComponents.count > ancestorComponents.count else {
            return false
        }

        return candidateComponents.prefix(ancestorComponents.count)
            .elementsEqual(ancestorComponents)
    }

    private static func validatedDestinationDirectory(
        _ destinationDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        guard Self.isLocalFileURL(destinationDirectoryURL) else {
            throw FileOperationError.destinationMustBeFileURL(
                value: destinationDirectoryURL.absoluteString
            )
        }

        let destinationDirectoryURL = destinationDirectoryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var destinationIsDirectory: ObjCBool = false

        guard fileManager.fileExists(
            atPath: destinationDirectoryURL.path,
            isDirectory: &destinationIsDirectory
        ) else {
            throw FileOperationError.destinationNotFound(path: destinationDirectoryURL.path)
        }

        guard destinationIsDirectory.boolValue else {
            throw FileOperationError.destinationIsNotDirectory(
                path: destinationDirectoryURL.path
            )
        }

        return destinationDirectoryURL
    }

    private static func uniqueCopyDestination(
        for sourceURL: URL,
        in destinationDirectoryURL: URL,
        sourceIsDirectory: Bool,
        fileManager: FileManager
    ) throws -> URL {
        try Task.checkCancellation()

        let originalURL = destinationDirectoryURL.appending(
            path: sourceURL.lastPathComponent,
            directoryHint: sourceIsDirectory ? .isDirectory : .notDirectory
        )

        guard Self.itemExists(at: originalURL, fileManager: fileManager) else {
            return originalURL
        }

        let name: String
        let extensionSuffix: String

        if sourceIsDirectory || sourceURL.pathExtension.isEmpty {
            name = sourceURL.lastPathComponent
            extensionSuffix = ""
        } else {
            name = sourceURL.deletingPathExtension().lastPathComponent
            extensionSuffix = ".\(sourceURL.pathExtension)"
        }

        var copyNumber = 1
        let maximumNameLength = Self.maximumFileNameLength(
            in: destinationDirectoryURL
        )

        while true {
            try Task.checkCancellation()

            let suffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
            let candidateName = Self.fileName(
                baseName: name,
                suffix: suffix,
                extensionSuffix: extensionSuffix,
                maximumUTF8Length: maximumNameLength
            )
            let candidateURL = destinationDirectoryURL.appending(
                path: candidateName,
                directoryHint: sourceIsDirectory ? .isDirectory : .notDirectory
            )

            if Self.itemExists(at: candidateURL, fileManager: fileManager) == false {
                return candidateURL
            }

            copyNumber += 1
        }
    }

    private static func uniqueCopyStagingURL(
        in destinationDirectoryURL: URL,
        fileManager: FileManager
    ) -> URL {
        while true {
            let candidateURL = destinationDirectoryURL.appending(
                path: ".finallyexplorer-copy-\(UUID().uuidString)"
            )

            if Self.itemExists(at: candidateURL, fileManager: fileManager) == false {
                return candidateURL
            }
        }
    }

    /// `fileExists(atPath:)` follows symlinks, so it reports dangling links as
    /// absent. Directory entries must still reserve their names and be movable.
    private static func itemExists(
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isDestinationCollision(_ error: any Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileWriteFileExists.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST))
    }

    private static func isCrossDeviceMove(_ error: NSError) -> Bool {
        error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV)
    }

    /// `FileManager.moveItem` ultimately uses overwrite-capable rename semantics
    /// on a single volume. `RENAME_EXCL` makes claiming the final name atomic,
    /// so concurrent operations can never replace an item that won the race.
    private static func moveItemExclusively(
        at sourceURL: URL,
        to destinationURL: URL
    ) throws {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }

        guard result == 0 else {
            let errorCode = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errorCode),
                userInfo: [NSFilePathErrorKey: destinationURL.path]
            )
        }
    }

    /// Cross-volume rename is impossible. Copy into a hidden item on the
    /// destination volume, claim the visible name exclusively, then remove the
    /// source. If source removal fails, best-effort rollback preserves move
    /// semantics instead of silently reporting success with two visible items.
    private static func moveAcrossVolumes(
        sourceURL: URL,
        destinationURL: URL,
        destinationDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let stagingURL = Self.uniqueCopyStagingURL(
            in: destinationDirectoryURL,
            fileManager: fileManager
        )

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try Task.checkCancellation()
            try Self.moveItemExclusively(at: stagingURL, to: destinationURL)

            do {
                try fileManager.removeItem(at: sourceURL)
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        guard let host = url.host(percentEncoded: false), host.isEmpty == false else {
            return true
        }

        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    private static func maximumFileNameLength(in directoryURL: URL) -> Int {
        let result = directoryURL.path.withCString {
            pathconf($0, _PC_NAME_MAX)
        }

        // APFS/HFS normally report 255. A conservative fallback keeps copy
        // suffixes valid on file systems that do not expose the limit.
        return result > 0 ? Int(result) : 255
    }

    private static func fileName(
        baseName: String,
        suffix: String,
        extensionSuffix: String,
        maximumUTF8Length: Int
    ) -> String {
        let suffixLength = suffix.utf8.count
        guard suffixLength < maximumUTF8Length else {
            return String(decoding: suffix.utf8.prefix(maximumUTF8Length), as: UTF8.self)
        }

        var fittedExtension = extensionSuffix
        let minimumBaseLength = min(baseName.utf8.first.map { _ in 1 } ?? 0, 1)
        let maximumExtensionLength = max(
            0,
            maximumUTF8Length - suffixLength - minimumBaseLength
        )
        if fittedExtension.utf8.count > maximumExtensionLength {
            fittedExtension = Self.utf8Prefix(
                fittedExtension,
                maximumLength: maximumExtensionLength
            )
        }

        let maximumBaseLength = max(
            0,
            maximumUTF8Length - suffixLength - fittedExtension.utf8.count
        )
        var fittedBase = Self.utf8Prefix(
            baseName,
            maximumLength: maximumBaseLength
        )
        if fittedBase.isEmpty, maximumBaseLength > 0 {
            fittedBase = "_"
        }

        return "\(fittedBase)\(suffix)\(fittedExtension)"
    }

    private static func utf8Prefix(
        _ value: String,
        maximumLength: Int
    ) -> String {
        guard maximumLength > 0, value.utf8.count > maximumLength else {
            return maximumLength > 0 ? value : ""
        }

        var result = ""
        var length = 0

        for character in value {
            let characterLength = String(character).utf8.count
            guard length + characterLength <= maximumLength else { break }
            result.append(character)
            length += characterLength
        }

        return result
    }
}
