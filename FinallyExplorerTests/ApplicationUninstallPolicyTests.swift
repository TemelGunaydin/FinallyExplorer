//
//  ApplicationUninstallPolicyTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

struct ApplicationUninstallPolicyTests {
    @Test(
        "A real application directly inside an allowed Applications folder can be uninstalled",
        arguments: ["Editor.app", "Editor.APP"]
    )
    func allowsApplicationBundleInConfiguredRoot(name: String) {
        let root = URL(filePath: "/tmp/Test Applications", directoryHint: .isDirectory)
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: URL(filePath: "/Applications/FinallyExplorer.app"),
            isApplication: { _ in true },
            isDeletable: { _ in true }
        )
        let item = makeItem(
            at: root.appending(path: name, directoryHint: .isDirectory),
            isDirectory: true,
            isApplicationBundle: true
        )

        #expect(policy.allowsUninstall(of: item))
    }

    @Test("Application lookalikes are not offered the uninstall action")
    func rejectsApplicationLookalikes() {
        let root = URL(filePath: "/tmp/Test Applications", directoryHint: .isDirectory)
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: nil,
            isApplication: { _ in true },
            isDeletable: { _ in true }
        )
        let ordinaryFolder = makeItem(
            at: root.appending(path: "Not an App", directoryHint: .isDirectory),
            isDirectory: true,
            isApplicationBundle: false
        )
        let misleadingExtension = makeItem(
            at: root.appending(path: "Lookalike.app", directoryHint: .isDirectory),
            isDirectory: true,
            isApplicationBundle: false
        )
        let regularFile = makeItem(
            at: root.appending(path: "Archive.app", directoryHint: .notDirectory),
            isDirectory: false,
            isApplicationBundle: false
        )

        #expect(policy.allowsUninstall(of: ordinaryFolder) == false)
        #expect(policy.allowsUninstall(of: misleadingExtension) == false)
        #expect(policy.allowsUninstall(of: regularFile) == false)
    }

    @Test("Applications outside the direct configured root stay ordinary Trash items")
    func rejectsApplicationsOutsideConfiguredRoot() {
        let root = URL(filePath: "/tmp/Test Applications", directoryHint: .isDirectory)
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: nil,
            isApplication: { _ in true },
            isDeletable: { _ in true }
        )
        let outsideRoot = makeItem(
            at: URL(filePath: "/tmp/Elsewhere/Editor.app", directoryHint: .isDirectory),
            isDirectory: true,
            isApplicationBundle: true
        )
        let prefixConfusion = makeItem(
            at: URL(
                filePath: "/tmp/Test Applications Backup/Editor.app",
                directoryHint: .isDirectory
            ),
            isDirectory: true,
            isApplicationBundle: true
        )
        let nestedApplication = makeItem(
            at: root.appending(
                path: "Utilities/Editor.app",
                directoryHint: .isDirectory
            ),
            isDirectory: true,
            isApplicationBundle: true
        )

        #expect(policy.allowsUninstall(of: outsideRoot) == false)
        #expect(policy.allowsUninstall(of: prefixConfusion) == false)
        #expect(policy.allowsUninstall(of: nestedApplication) == false)
        #expect(policy.availability(for: outsideRoot) == .notApplicable)
    }

    @Test("The running application cannot uninstall itself")
    func rejectsRunningApplication() {
        let root = URL(filePath: "/Applications", directoryHint: .isDirectory)
        let runningApplicationURL = root.appending(
            path: "FinallyExplorer.app",
            directoryHint: .isDirectory
        )
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: runningApplicationURL,
            isApplication: { _ in true },
            isDeletable: { _ in true }
        )
        let item = makeItem(
            at: runningApplicationURL,
            isDirectory: true,
            isApplicationBundle: true
        )

        #expect(policy.allowsUninstall(of: item) == false)
        #expect(policy.availability(for: item) == .unavailable)
        #expect(policy.availability(for: runningApplicationURL) == .unavailable)
    }

    @Test("Stale metadata cannot make a fake application uninstallable")
    func rejectsApplicationThatFailsFreshValidation() {
        let root = URL(filePath: "/Applications", directoryHint: .isDirectory)
        let applicationURL = root.appending(
            path: "Fake.app",
            directoryHint: .isDirectory
        )
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: nil,
            isApplication: { _ in false },
            isDeletable: { _ in true }
        )
        let item = makeItem(
            at: applicationURL,
            isDirectory: true,
            isApplicationBundle: true
        )

        #expect(policy.allowsUninstall(of: item) == false)
        #expect(policy.availability(for: item) == .unavailable)
        #expect(policy.availability(for: applicationURL) == .unavailable)
    }

    @Test("An application without removal permission is not offered uninstall")
    func rejectsApplicationWithoutRemovalPermission() {
        let root = URL(filePath: "/Applications", directoryHint: .isDirectory)
        let applicationURL = root.appending(
            path: "Managed App.app",
            directoryHint: .isDirectory
        )
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [root],
            runningApplicationURL: nil,
            isApplication: { _ in true },
            isDeletable: { _ in false }
        )
        let item = makeItem(
            at: applicationURL,
            isDirectory: true,
            isApplicationBundle: true
        )

        #expect(policy.allowsUninstall(of: item) == false)
        #expect(policy.availability(for: item) == .unavailable)
    }

    @Test("System applications are protected from every destructive menu action")
    func protectsSystemApplication() {
        let systemApplications = URL(
            filePath: "/System/Applications",
            directoryHint: .isDirectory
        )
        let item = makeItem(
            at: systemApplications.appending(
                path: "Utilities/System Information.app",
                directoryHint: .isDirectory
            ),
            isDirectory: true,
            isApplicationBundle: true
        )
        let policy = ApplicationUninstallPolicy(
            applicationDirectoryURLs: [URL(filePath: "/Applications")],
            runningApplicationURL: nil,
            isApplication: { _ in true },
            isDeletable: { _ in true }
        )

        #expect(policy.availability(for: item) == .unavailable)
    }

    private func makeItem(
        at url: URL,
        isDirectory: Bool,
        isApplicationBundle: Bool
    ) -> FileItem {
        FileItem(
            url: url,
            isDirectory: isDirectory,
            isImage: false,
            fileSize: nil,
            modificationDate: nil,
            isApplicationBundle: isApplicationBundle
        )
    }
}
