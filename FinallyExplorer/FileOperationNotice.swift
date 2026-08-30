//
//  FileOperationNotice.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct FileOperationNotice: Equatable, Identifiable, Sendable {
    let id: UUID
    let message: String
    let systemImage: String

    init(
        id: UUID = UUID(),
        message: String,
        systemImage: String
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
    }
}
