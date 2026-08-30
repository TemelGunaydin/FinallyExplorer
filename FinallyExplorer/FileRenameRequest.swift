//
//  FileRenameRequest.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct FileRenameRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL

    init(id: UUID = UUID(), sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL.standardizedFileURL
    }

    var originalName: String { sourceURL.lastPathComponent }
}
