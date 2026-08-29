//
//  ExplorerLaunchConfigurationTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct ExplorerLaunchConfigurationTests {
    @Test("Normal launches ignore UI-only environment values")
    func normalLaunchDoesNotReadUIConfiguration() {
        let environment = LaunchEnvironmentSpy(
            arguments: ["FinallyExplorer"],
            environment: [
                ExplorerLaunchConfiguration.fixtureRootEnvironmentKey: "/not/a/real/fixture",
                ExplorerLaunchConfiguration.defaultsSuiteEnvironmentKey: "ui-tests.defaults"
            ]
        )

        let configuration = ExplorerLaunchConfiguration(environment: environment)

        #expect(configuration.isUITesting == false)
        #expect(configuration.fixtureRoot == nil)
        #expect(configuration.defaultsSuiteName == nil)
        #expect(configuration.initialPlace == .downloads)
        #expect(environment.environmentReadCount == 0)
    }

    @Test("UI launch uses a verified local fixture directory and defaults suite")
    func uiLaunchUsesValidFixtureDirectory() throws {
        let fixtureRoot = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let configuration = ExplorerLaunchConfiguration(
            environment: StaticLaunchEnvironment(
                arguments: ["FinallyExplorer", ExplorerLaunchConfiguration.uiTestingArgument],
                environment: [
                    ExplorerLaunchConfiguration.fixtureRootEnvironmentKey: fixtureRoot.path,
                    ExplorerLaunchConfiguration.defaultsSuiteEnvironmentKey: "  ui-tests.defaults  "
                ]
            )
        )

        #expect(configuration.isUITesting)
        #expect(configuration.fixtureRoot == fixtureRoot.standardizedFileURL)
        #expect(configuration.defaultsSuiteName == "ui-tests.defaults")
        #expect(configuration.initialPlace.url == fixtureRoot.standardizedFileURL)
    }

    @Test("Invalid UI fixture roots safely use Downloads")
    func invalidFixtureRootsFallBackToDownloads() throws {
        let parentDirectory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: parentDirectory) }

        let regularFile = parentDirectory.appending(path: "regular-file.txt")
        try Data("fixture".utf8).write(to: regularFile)
        let missingDirectory = parentDirectory.appending(
            path: "missing-directory",
            directoryHint: .isDirectory
        )

        let invalidRoots = [
            "https://example.com/fixture",
            "file://example.com\(parentDirectory.path)",
            regularFile.path,
            missingDirectory.path,
            "relative-fixture",
            "   "
        ]

        for invalidRoot in invalidRoots {
            let configuration = ExplorerLaunchConfiguration(
                environment: StaticLaunchEnvironment(
                    arguments: [ExplorerLaunchConfiguration.uiTestingArgument],
                    environment: [
                        ExplorerLaunchConfiguration.fixtureRootEnvironmentKey: invalidRoot
                    ]
                )
            )

            #expect(configuration.isUITesting)
            #expect(configuration.fixtureRoot == nil)
            #expect(configuration.initialPlace == .downloads)
        }
    }

    @Test("File URL fixture roots are accepted only for local directories")
    func localFileURLFixtureRootIsAccepted() throws {
        let fixtureRoot = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let configuration = ExplorerLaunchConfiguration(
            environment: StaticLaunchEnvironment(
                arguments: [ExplorerLaunchConfiguration.uiTestingArgument],
                environment: [
                    ExplorerLaunchConfiguration.fixtureRootEnvironmentKey: fixtureRoot.absoluteString
                ]
            )
        )

        #expect(configuration.fixtureRoot == fixtureRoot.standardizedFileURL)
        #expect(configuration.initialPlace.url == fixtureRoot.standardizedFileURL)
    }

    @Test("Blank UI defaults suite names are ignored")
    func blankDefaultsSuiteNameIsIgnored() {
        let configuration = ExplorerLaunchConfiguration(
            environment: StaticLaunchEnvironment(
                arguments: [ExplorerLaunchConfiguration.uiTestingArgument],
                environment: [
                    ExplorerLaunchConfiguration.defaultsSuiteEnvironmentKey: " \n\t "
                ]
            )
        )

        #expect(configuration.defaultsSuiteName == nil)
    }

    private func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ExplorerLaunchConfigurationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}

private struct StaticLaunchEnvironment: ExplorerLaunchEnvironmentProviding {
    let arguments: [String]
    let environment: [String: String]
}

private final class LaunchEnvironmentSpy: ExplorerLaunchEnvironmentProviding {
    let arguments: [String]
    private let values: [String: String]
    private(set) var environmentReadCount = 0

    init(arguments: [String], environment: [String: String]) {
        self.arguments = arguments
        values = environment
    }

    var environment: [String: String] {
        environmentReadCount += 1
        return values
    }
}
