//
//  FileRenameRequest.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct FileRenameRequest: Equatable, Identifiable, Sendable {
    enum Intent: Equatable, Sendable {
        case renameExistingItem
        case createFolder(destinationDirectoryURL: URL)
    }

    let id: UUID
    let sourceURL: URL
    let intent: Intent

    init(id: UUID = UUID(), sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL.standardizedFileURL
        intent = .renameExistingItem
    }

    init(
        id: UUID = UUID(),
        newFolderIn destinationDirectoryURL: URL,
        suggestedName: String
    ) {
        self.id = id
        let destinationDirectoryURL = destinationDirectoryURL.standardizedFileURL
        sourceURL = destinationDirectoryURL.appending(
            path: suggestedName,
            directoryHint: .isDirectory
        )
        intent = .createFolder(
            destinationDirectoryURL: destinationDirectoryURL
        )
    }

    var originalName: String { sourceURL.lastPathComponent }

    var isNewFolder: Bool {
        if case .createFolder = intent {
            true
        } else {
            false
        }
    }
}
