//
//  FFFRootScanPolicy.swift
//  FinallyExplorer
//

import Foundation

/// Enables broad scans only when the selected root explicitly requires them.
/// This keeps normal folder searches conservative while allowing global and
/// Home searches to opt into the native engine's guarded scan modes.
nonisolated enum FFFRootScanPolicy {
    static func allowsFileSystemRootScanning(for rootURL: URL) -> Bool {
        canonicalPath(for: rootURL) == "/"
    }

    static func allowsHomeDirectoryScanning(
        for rootURL: URL,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        canonicalPath(for: rootURL) == canonicalPath(for: homeDirectoryURL)
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)
    }
}
