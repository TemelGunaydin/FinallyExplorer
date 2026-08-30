//
//  ExplorerLaunchConfiguration.swift
//  FinallyExplorer
//

import Foundation

/// Supplies launch values without coupling configuration parsing to `ProcessInfo`.
///
/// UI automation can provide a fixture directory and isolated defaults suite, while
/// unit tests can supply deterministic values without changing the process state.
protocol ExplorerLaunchEnvironmentProviding {
    var arguments: [String] { get }
    var environment: [String: String] { get }
}

struct ProcessInfoLaunchEnvironment: ExplorerLaunchEnvironmentProviding {
    let arguments: [String]
    let environment: [String: String]

    init(processInfo: ProcessInfo = .processInfo) {
        arguments = processInfo.arguments
        environment = processInfo.environment
    }
}

struct ExplorerLaunchConfiguration: Equatable, Sendable {
    static let uiTestingArgument = "--ui-testing"
    static let fixtureRootEnvironmentKey = "FINALLY_EXPLORER_UI_FIXTURE_ROOT"
    static let mountedVolumeEnvironmentKey = "FINALLY_EXPLORER_UI_MOUNTED_VOLUME"
    static let defaultsSuiteEnvironmentKey = "FINALLY_EXPLORER_UI_DEFAULTS_SUITE"
    static let nearbyPeerNameEnvironmentKey = "FINALLY_EXPLORER_UI_NEARBY_PEER"

    let isUITesting: Bool
    let fixtureRoot: URL?
    let mountedVolumeFixture: URL?
    let defaultsSuiteName: String?
    let nearbyPeerName: String?

    init(environment: some ExplorerLaunchEnvironmentProviding) {
        let isUITesting = environment.arguments.contains(Self.uiTestingArgument)
        self.isUITesting = isUITesting

        guard isUITesting else {
            fixtureRoot = nil
            mountedVolumeFixture = nil
            defaultsSuiteName = nil
            nearbyPeerName = nil
            return
        }

        fixtureRoot = Self.validFixtureRoot(
            from: environment.environment[Self.fixtureRootEnvironmentKey]
        )
        mountedVolumeFixture = Self.validFixtureRoot(
            from: environment.environment[Self.mountedVolumeEnvironmentKey]
        )
        defaultsSuiteName = Self.nonEmptyValue(
            environment.environment[Self.defaultsSuiteEnvironmentKey]
        )
        nearbyPeerName = Self.nonEmptyValue(
            environment.environment[Self.nearbyPeerNameEnvironmentKey]
        )
    }

    init() {
        self.init(environment: ProcessInfoLaunchEnvironment())
    }

    var initialPlace: SidebarPlace {
        guard let fixtureRoot else { return .downloads }
        return .favorite(SidebarFavorite(directoryURL: fixtureRoot))
    }

    private static func validFixtureRoot(from rawValue: String?) -> URL? {
        guard let rawValue = nonEmptyValue(rawValue) else { return nil }

        let candidate: URL
        if let parsedURL = URL(string: rawValue), parsedURL.scheme != nil {
            let host = parsedURL.host?.lowercased()
            guard parsedURL.isFileURL,
                  host == nil || host == "" || host == "localhost" else {
                return nil
            }
            candidate = parsedURL
        } else {
            guard rawValue.hasPrefix("/") else { return nil }
            candidate = URL(filePath: rawValue, directoryHint: .isDirectory)
        }

        let normalizedURL = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard normalizedURL.isFileURL else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: normalizedURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }

        return normalizedURL
    }

    private static func nonEmptyValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
