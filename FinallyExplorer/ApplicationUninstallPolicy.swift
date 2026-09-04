//
//  ApplicationUninstallPolicy.swift
//  FinallyExplorer
//

import Foundation

/// Limits the uninstall affordance to application bundles in user-managed
/// Applications folders. The operation itself remains a recoverable Trash move.
nonisolated struct ApplicationUninstallPolicy: Sendable {
    private let applicationDirectoryPaths: Set<String>
    private let protectedApplicationDirectoryPaths: Set<String>
    private let runningApplicationPath: String?
    private let isApplication: @Sendable (URL) -> Bool
    private let isDeletable: @Sendable (String) -> Bool

    init(
        applicationDirectoryURLs: [URL],
        protectedApplicationDirectoryURLs: [URL] = [
            URL(filePath: "/System/Applications", directoryHint: .isDirectory)
        ],
        runningApplicationURL: URL?,
        isApplication: @escaping @Sendable (URL) -> Bool = { url in
            let values = try? url.resourceValues(
                forKeys: [.isApplicationKey, .isSymbolicLinkKey]
            )
            return values?.isApplication == true
                && values?.isSymbolicLink != true
        },
        isDeletable: @escaping @Sendable (String) -> Bool = { path in
            FileManager.default.isDeletableFile(atPath: path)
        }
    ) {
        applicationDirectoryPaths = Set(
            applicationDirectoryURLs.map(Self.resolvedPath)
        )
        protectedApplicationDirectoryPaths = Set(
            protectedApplicationDirectoryURLs.map(Self.resolvedPath)
        )
        runningApplicationPath = runningApplicationURL.map(Self.resolvedPath)
        self.isApplication = isApplication
        self.isDeletable = isDeletable
    }

    static func live(
        additionalApplicationDirectoryURLs: [URL] = []
    ) -> Self {
        let fileManager = FileManager.default
        let applicationDirectoryURLs = fileManager.urls(
            for: .applicationDirectory,
            in: .localDomainMask
        ) + fileManager.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ) + additionalApplicationDirectoryURLs

        return Self(
            applicationDirectoryURLs: applicationDirectoryURLs,
            runningApplicationURL: Bundle.main.bundleURL
        )
    }

    func allowsUninstall(of item: FileItem) -> Bool {
        availability(for: item) == .available
    }

    func availability(for url: URL) -> ApplicationUninstallAvailability {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "app" else {
            return .notApplicable
        }

        let applicationPath = Self.resolvedPath(url)
        let parentPath = Self.resolvedPath(
            url.resolvingSymlinksInPath().deletingLastPathComponent()
        )
        if applicationPath == runningApplicationPath
            || protectedApplicationDirectoryPaths.contains(where: {
                Self.isSameOrDescendantPath(applicationPath, of: $0)
            }) {
            return .unavailable
        }

        guard applicationDirectoryPaths.contains(parentPath) else {
            return .notApplicable
        }

        guard isApplication(url), isDeletable(applicationPath) else {
            return .unavailable
        }

        return .available
    }

    func availability(
        for item: FileItem
    ) -> ApplicationUninstallAvailability {
        guard item.url.isFileURL,
              item.url.pathExtension.lowercased() == "app" else {
            return .notApplicable
        }

        let currentAvailability = availability(for: item.url)
        guard item.isApplicationBundle else {
            return currentAvailability == .available
                ? .unavailable
                : currentAvailability
        }

        return currentAvailability
    }

    private static func resolvedPath(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)

        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }

    private static func isSameOrDescendantPath(
        _ candidatePath: String,
        of rootPath: String
    ) -> Bool {
        candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath + "/")
    }
}
