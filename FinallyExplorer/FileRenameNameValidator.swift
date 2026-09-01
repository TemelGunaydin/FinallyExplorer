//
//  FileRenameNameValidator.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum FileRenameNameValidator {
    enum ValidationError: LocalizedError, Equatable, Sendable {
        case empty
        case reserved
        case containsPathSeparator
        case containsColon
        case containsNullCharacter
        case tooLong(maximumUTF8Length: Int)

        var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a name."
            case .reserved:
                "The names “.” and “..” are reserved by the file system."
            case .containsPathSeparator:
                "A name cannot contain a slash (/)."
            case .containsColon:
                "A name cannot contain a colon (:)."
            case .containsNullCharacter:
                "A name cannot contain a null character."
            case let .tooLong(maximumUTF8Length):
                "The name is longer than this disk’s \(maximumUTF8Length)-byte limit."
            }
        }
    }

    static func validate(
        _ name: String,
        maximumUTF8Length: Int = 255
    ) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty
        }
        if name == "." || name == ".." {
            throw ValidationError.reserved
        }
        if name.contains("/") {
            throw ValidationError.containsPathSeparator
        }
        if name.contains(":") {
            throw ValidationError.containsColon
        }
        if name.contains("\0") {
            throw ValidationError.containsNullCharacter
        }
        if name.utf8.count > maximumUTF8Length {
            throw ValidationError.tooLong(
                maximumUTF8Length: maximumUTF8Length
            )
        }
    }

    static func validationMessage(for name: String) -> String? {
        do {
            try validate(name)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func suggestedNewFolderName(existingNames: [String]) -> String {
        var folderNumber = 1

        while true {
            let candidate = folderNumber == 1
                ? "New Folder"
                : "New Folder \(folderNumber)"
            let isOccupied = existingNames.contains {
                $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame
            }

            if isOccupied == false {
                return candidate
            }
            folderNumber += 1
        }
    }
}
