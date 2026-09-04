//
//  FileOpenApplication.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct FileOpenApplication: Hashable, Identifiable, Sendable {
    let name: String
    let applicationURL: URL

    var id: String {
        applicationURL.standardizedFileURL
            .path(percentEncoded: false)
    }
}
