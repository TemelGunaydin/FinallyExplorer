//
//  FileRenameResult.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct FileRenameResult: Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL
    ) {
        self.id = id
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL.standardizedFileURL
    }
}
