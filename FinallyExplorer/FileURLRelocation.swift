//
//  FileURLRelocation.swift
//  FinallyExplorer
//

import Foundation

/// Rebases an item or one of its descendants after an in-place folder rename.
nonisolated enum FileURLRelocation {
    static func rebase(
        _ candidateURL: URL,
        from sourceURL: URL,
        to destinationURL: URL
    ) -> URL? {
        let candidateURL = candidateURL.standardizedFileURL
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        let candidateComponents = candidateURL.pathComponents
        let sourceComponents = sourceURL.pathComponents

        guard candidateURL.isFileURL,
              sourceURL.isFileURL,
              destinationURL.isFileURL,
              candidateComponents.count >= sourceComponents.count,
              candidateComponents.prefix(sourceComponents.count)
                .elementsEqual(sourceComponents) else {
            return nil
        }

        return candidateComponents.dropFirst(sourceComponents.count).reduce(
            destinationURL
        ) { partialURL, component in
            partialURL.appending(path: component)
        }.standardizedFileURL
    }
}
