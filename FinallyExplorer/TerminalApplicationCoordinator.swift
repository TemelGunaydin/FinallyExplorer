//
//  TerminalApplicationCoordinator.swift
//  FinallyExplorer
//

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

nonisolated struct TerminalApplication: Hashable, Identifiable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let applicationURL: URL

    var id: String {
        TerminalApplicationMetadata.normalizedBundleIdentifier(bundleIdentifier)
            ?? applicationURL.standardizedFileURL.path
    }
}

nonisolated struct TerminalApplicationCandidate: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let applicationURL: URL
}

nonisolated enum TerminalApplicationClassifier {
    static func isTerminal(documentTypeRoles: [String]) -> Bool {
        documentTypeRoles.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare("Shell", options: .caseInsensitive) == .orderedSame
        }
    }
}

private nonisolated enum TerminalApplicationMetadata {
    static func normalizedBundleIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }

        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func firstNonemptyName(_ candidates: String?...) -> String {
        for candidate in candidates {
            let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, normalized.isEmpty == false {
                return normalized
            }
        }

        return "Terminal"
    }
}

nonisolated enum TerminalApplicationError: LocalizedError, Equatable, Sendable {
    case invalidFolderURL(url: String)
    case folderNotFound(path: String)
    case destinationIsNotFolder(path: String)
    case applicationNotFound(name: String)
    case openFailed(applicationName: String, path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidFolderURL(url):
            "Only a local folder can be opened in a terminal.\n\nURL: \(url)"
        case let .folderNotFound(path):
            "The folder could not be found.\n\nPath: \(path)"
        case let .destinationIsNotFolder(path):
            "Only folders can be opened in a terminal.\n\nPath: \(path)"
        case let .applicationNotFound(name):
            "\(name) is no longer installed."
        case let .openFailed(applicationName, path, reason):
            "Unable to open the folder in \(applicationName): \(reason)\n\nPath: \(path)"
        }
    }
}

@MainActor
protocol TerminalWorkspace: AnyObject {
    func terminalApplicationCandidates() -> [TerminalApplicationCandidate]

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL?

    func openDirectory(
        _ directoryURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws
}

@MainActor
final class SystemTerminalWorkspace: TerminalWorkspace {
    func terminalApplicationCandidates() -> [TerminalApplicationCandidate] {
        NSWorkspace.shared.urlsForApplications(toOpen: .unixExecutable)
            .compactMap(Self.terminalApplicationCandidate)
    }

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openDirectory(
        _ directoryURL: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true

        _ = try await NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    static func terminalApplicationCandidate(
        at applicationURL: URL
    ) -> TerminalApplicationCandidate? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }

        let documentTypes = bundle.object(
            forInfoDictionaryKey: "CFBundleDocumentTypes"
        ) as? [[String: Any]] ?? []
        let documentTypeRoles = documentTypes.compactMap {
            $0["CFBundleTypeRole"] as? String
        }

        guard TerminalApplicationClassifier.isTerminal(
            documentTypeRoles: documentTypeRoles
        ) else {
            return nil
        }

        let name = TerminalApplicationMetadata.firstNonemptyName(
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            applicationURL.deletingPathExtension().lastPathComponent
        )

        return TerminalApplicationCandidate(
            name: name,
            bundleIdentifier: TerminalApplicationMetadata.normalizedBundleIdentifier(
                bundle.bundleIdentifier
            ),
            applicationURL: applicationURL
        )
    }
}

@MainActor
struct TerminalApplicationService {
    private let workspace: any TerminalWorkspace

    init(workspace: any TerminalWorkspace) {
        self.workspace = workspace
    }

    func installedApplications() -> [TerminalApplication] {
        var seenIdentifiers: Set<String> = []
        var seenPaths: Set<String> = []

        return workspace.terminalApplicationCandidates().compactMap { candidate in
            let bundleIdentifier = TerminalApplicationMetadata.normalizedBundleIdentifier(
                candidate.bundleIdentifier
            )
            let path = candidate.applicationURL.standardizedFileURL.path
            let alreadySeenIdentifier = bundleIdentifier.map {
                seenIdentifiers.contains($0)
            } ?? false
            let alreadySeenPath = seenPaths.contains(path)

            if let bundleIdentifier {
                seenIdentifiers.insert(bundleIdentifier)
            }
            seenPaths.insert(path)

            guard alreadySeenIdentifier == false, alreadySeenPath == false else {
                return nil
            }

            return TerminalApplication(
                name: TerminalApplicationMetadata.firstNonemptyName(
                    candidate.name,
                    candidate.applicationURL.deletingPathExtension().lastPathComponent
                ),
                bundleIdentifier: bundleIdentifier,
                applicationURL: candidate.applicationURL
            )
        }
        .sorted(by: Self.applicationDisplayOrder)
    }

    func open(
        directoryURL: URL,
        in application: TerminalApplication
    ) async throws {
        try Task.checkCancellation()

        guard Self.isLocalFileURL(directoryURL) else {
            throw TerminalApplicationError.invalidFolderURL(
                url: directoryURL.absoluteString
            )
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ) else {
            throw TerminalApplicationError.folderNotFound(path: directoryURL.path)
        }

        guard isDirectory.boolValue else {
            throw TerminalApplicationError.destinationIsNotFolder(path: directoryURL.path)
        }

        let currentApplicationURL: URL

        if let bundleIdentifier = TerminalApplicationMetadata.normalizedBundleIdentifier(
            application.bundleIdentifier
        ) {
            guard let resolvedApplicationURL = workspace.applicationURL(
                withBundleIdentifier: bundleIdentifier
            ) else {
                throw TerminalApplicationError.applicationNotFound(name: application.name)
            }

            currentApplicationURL = resolvedApplicationURL
        } else {
            var isApplicationDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: application.applicationURL.path,
                isDirectory: &isApplicationDirectory
            ), isApplicationDirectory.boolValue else {
                throw TerminalApplicationError.applicationNotFound(name: application.name)
            }

            currentApplicationURL = application.applicationURL
        }

        guard Self.isLocalFileURL(currentApplicationURL) else {
            throw TerminalApplicationError.applicationNotFound(name: application.name)
        }

        try Task.checkCancellation()

        do {
            try await workspace.openDirectory(
                directoryURL,
                withApplicationAt: currentApplicationURL
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TerminalApplicationError.openFailed(
                applicationName: application.name,
                path: directoryURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private static func applicationDisplayOrder(
        _ lhs: TerminalApplication,
        _ rhs: TerminalApplication
    ) -> Bool {
        let localizedComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if localizedComparison != .orderedSame {
            return localizedComparison == .orderedAscending
        }

        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        return lhs.id < rhs.id
    }

    private static func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let host = url.host, host.isEmpty == false else { return true }

        return host.compare("localhost", options: .caseInsensitive) == .orderedSame
    }
}

@MainActor
@Observable
final class TerminalApplicationCoordinator {
    private(set) var installedApplications: [TerminalApplication] = []
    private(set) var isOpening = false

    var isErrorPresented = false
    private(set) var errorMessage = ""

    @ObservationIgnored private let service: TerminalApplicationService

    init(workspace: (any TerminalWorkspace)? = nil) {
        let workspace = workspace ?? SystemTerminalWorkspace()
        service = TerminalApplicationService(workspace: workspace)
        installedApplications = service.installedApplications()
    }

    func refresh() {
        installedApplications = service.installedApplications()
    }

    @discardableResult
    func open(
        _ directoryURL: URL,
        in application: TerminalApplication
    ) -> Task<Void, Never>? {
        guard isOpening == false else { return nil }

        isOpening = true
        errorMessage = ""
        isErrorPresented = false
        let service = service

        return Task(name: "Open folder in \(application.name)") { [weak self, service] in
            do {
                try await service.open(directoryURL: directoryURL, in: application)
                self?.finishOpen(errorMessage: nil)
            } catch is CancellationError {
                self?.finishOpen(errorMessage: nil)
            } catch {
                self?.finishOpen(errorMessage: error.localizedDescription)
            }
        }
    }

    private func finishOpen(errorMessage: String?) {
        isOpening = false

        if let errorMessage {
            self.errorMessage = errorMessage
            isErrorPresented = true
        } else {
            self.errorMessage = ""
            isErrorPresented = false
        }
    }
}
