//
//  FileOpenApplicationCoordinator.swift
//  FinallyExplorer
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class FileOpenApplicationCoordinator {
    var isErrorPresented = false
    private(set) var errorMessage = ""

    private static let maximumCachedFileCount = 12

    private var activeOpenCount = 0
    private var applicationsByFilePath: [String: [FileOpenApplication]] = [:]
    private var cachedFilePaths: [String] = []
    @ObservationIgnored private let applicationLoader: @MainActor (URL) -> [FileOpenApplication]
    @ObservationIgnored private let fileOpener: @MainActor (URL, URL) async throws -> Void

    var isOpening: Bool {
        activeOpenCount > 0
    }

    convenience init() {
        self.init(
            applicationLoader: Self.systemApplications,
            fileOpener: Self.openUsingSystemWorkspace
        )
    }

    init(
        applicationLoader: @escaping @MainActor (URL) -> [FileOpenApplication],
        fileOpener: @escaping @MainActor (URL, URL) async throws -> Void
    ) {
        self.applicationLoader = applicationLoader
        self.fileOpener = fileOpener
    }

    func refreshApplications(for fileURL: URL) {
        let key = Self.fileKey(for: fileURL)
        applicationsByFilePath[key] = applicationLoader(fileURL)
        cachedFilePaths.removeAll { $0 == key }
        cachedFilePaths.append(key)

        while cachedFilePaths.count > Self.maximumCachedFileCount {
            let evictedKey = cachedFilePaths.removeFirst()
            applicationsByFilePath[evictedKey] = nil
        }
    }

    func applications(for fileURL: URL) -> [FileOpenApplication] {
        applicationsByFilePath[Self.fileKey(for: fileURL)] ?? []
    }

    func hasLoadedApplications(for fileURL: URL) -> Bool {
        applicationsByFilePath[Self.fileKey(for: fileURL)] != nil
    }

    @discardableResult
    func open(
        _ fileURL: URL,
        in application: FileOpenApplication
    ) -> Task<Void, Never>? {
        activeOpenCount += 1
        errorMessage = ""
        let fileOpener = fileOpener

        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer { activeOpenCount -= 1 }

            do {
                try await fileOpener(fileURL, application.applicationURL)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "“\(fileURL.lastPathComponent)” couldn’t be opened in "
                    + "\(application.name).\n\n\(error.localizedDescription)"
                isErrorPresented = true
            }
        }
    }

    private static func systemApplications(
        for fileURL: URL
    ) -> [FileOpenApplication] {
        resolvedApplications(
            from: NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        )
    }

    static func resolvedApplications(
        from applicationURLs: [URL]
    ) -> [FileOpenApplication] {
        var seenPaths: Set<String> = []

        return applicationURLs.compactMap { applicationURL in
            let normalizedURL = applicationURL.resolvingSymlinksInPath()
                .standardizedFileURL
            let path = normalizedURL.path(percentEncoded: false)
            guard normalizedURL.isFileURL,
                  seenPaths.insert(path).inserted else {
                return nil
            }

            let bundle = Bundle(url: normalizedURL)
            let name = firstNonemptyName(
                bundle?.object(
                    forInfoDictionaryKey: "CFBundleDisplayName"
                ) as? String,
                bundle?.object(
                    forInfoDictionaryKey: "CFBundleName"
                ) as? String,
                normalizedURL.deletingPathExtension().lastPathComponent
            )

            return FileOpenApplication(
                name: name,
                applicationURL: normalizedURL
            )
        }
    }

    private static func openUsingSystemWorkspace(
        fileURL: URL,
        applicationURL: URL
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = true

        _ = try await NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    private static func firstNonemptyName(_ candidates: String?...) -> String {
        for candidate in candidates {
            let trimmedName = candidate?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if let trimmedName, trimmedName.isEmpty == false {
                return trimmedName
            }
        }

        return "Application"
    }

    private static func fileKey(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
