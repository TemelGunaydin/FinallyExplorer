//
//  FileOpenApplicationCoordinatorTests.swift
//  FinallyExplorerTests
//

import Foundation
import Testing
@testable import FinallyExplorer

@MainActor
struct FileOpenApplicationCoordinatorTests {
    @Test("Compatible applications retain the system suitability order")
    func loadsCompatibleApplicationsForExactFile() {
        let fileURL = URL(filePath: "/tmp/Report.pdf")
        let expectedApplications = [
            FileOpenApplication(
                name: "Preview",
                applicationURL: URL(filePath: "/Applications/Preview.app")
            ),
            FileOpenApplication(
                name: "Acrobat",
                applicationURL: URL(filePath: "/Applications/Acrobat.app")
            ),
        ]
        var requestedFileURL: URL?
        let coordinator = FileOpenApplicationCoordinator(
            applicationLoader: { url in
                requestedFileURL = url
                return expectedApplications
            },
            fileOpener: { _, _ in }
        )

        #expect(coordinator.hasLoadedApplications(for: fileURL) == false)
        coordinator.refreshApplications(for: fileURL)

        #expect(requestedFileURL == fileURL)
        #expect(coordinator.hasLoadedApplications(for: fileURL))
        #expect(coordinator.applications(for: fileURL) == expectedApplications)
    }

    @Test("Compatible application results remain available for multiple files")
    func retainsResultsForMultipleFiles() {
        let firstFileURL = URL(filePath: "/tmp/First.txt")
        let secondFileURL = URL(filePath: "/tmp/Second.pdf")
        let textEdit = FileOpenApplication(
            name: "TextEdit",
            applicationURL: URL(filePath: "/System/Applications/TextEdit.app")
        )
        let preview = FileOpenApplication(
            name: "Preview",
            applicationURL: URL(filePath: "/System/Applications/Preview.app")
        )
        let coordinator = FileOpenApplicationCoordinator(
            applicationLoader: { url in
                url == firstFileURL ? [textEdit] : [preview]
            },
            fileOpener: { _, _ in }
        )

        coordinator.refreshApplications(for: firstFileURL)
        coordinator.refreshApplications(for: secondFileURL)

        #expect(coordinator.applications(for: firstFileURL) == [textEdit])
        #expect(coordinator.applications(for: secondFileURL) == [preview])
    }

    @Test("Workspace candidates are normalized, deduplicated, and retain order")
    func resolvesWorkspaceCandidates() {
        let previewURL = URL(filePath: "/Applications/Preview.app")
        let duplicatePreviewURL = URL(
            filePath: "/Applications/../Applications/Preview.app"
        )
        let textEditURL = URL(filePath: "/Applications/TextEdit.app")

        let applications = FileOpenApplicationCoordinator.resolvedApplications(
            from: [
                previewURL,
                URL(string: "https://example.com/Viewer.app")!,
                duplicatePreviewURL,
                textEditURL,
            ]
        )

        #expect(applications.map(\.applicationURL) == [previewURL, textEditURL])
        #expect(applications.map(\.name) == ["Preview", "TextEdit"])
    }

    @Test("Opening forwards the selected file and application")
    func opensFileInSelectedApplication() async throws {
        let fileURL = URL(filePath: "/tmp/Notes.txt")
        let application = FileOpenApplication(
            name: "TextEdit",
            applicationURL: URL(filePath: "/System/Applications/TextEdit.app")
        )
        var openedFileURL: URL?
        var openedApplicationURL: URL?
        let coordinator = FileOpenApplicationCoordinator(
            applicationLoader: { _ in [application] },
            fileOpener: { fileURL, applicationURL in
                openedFileURL = fileURL
                openedApplicationURL = applicationURL
            }
        )

        let task = try #require(coordinator.open(fileURL, in: application))
        await task.value

        #expect(openedFileURL == fileURL)
        #expect(openedApplicationURL == application.applicationURL)
        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented == false)
    }

    @Test("An application launch failure is surfaced by the app")
    func presentsOpenFailure() async throws {
        let fileURL = URL(filePath: "/tmp/Notes.txt")
        let application = FileOpenApplication(
            name: "Fixture Viewer",
            applicationURL: URL(filePath: "/Applications/Fixture Viewer.app")
        )
        let coordinator = FileOpenApplicationCoordinator(
            applicationLoader: { _ in [application] },
            fileOpener: { _, _ in
                throw CocoaError(.fileReadNoSuchFile)
            }
        )

        let task = try #require(coordinator.open(fileURL, in: application))
        await task.value

        #expect(coordinator.isOpening == false)
        #expect(coordinator.isErrorPresented)
        #expect(coordinator.errorMessage.contains("Notes.txt"))
        #expect(coordinator.errorMessage.contains("Fixture Viewer"))
    }

    @Test("Open requests from different windows do not reject each other")
    func allowsConcurrentOpenRequests() async throws {
        let firstFileURL = URL(filePath: "/tmp/First.txt")
        let secondFileURL = URL(filePath: "/tmp/Second.txt")
        let application = FileOpenApplication(
            name: "TextEdit",
            applicationURL: URL(filePath: "/System/Applications/TextEdit.app")
        )
        var openedFiles: [URL] = []
        let coordinator = FileOpenApplicationCoordinator(
            applicationLoader: { _ in [application] },
            fileOpener: { fileURL, _ in
                openedFiles.append(fileURL)
                try await Task.sleep(for: .milliseconds(20))
            }
        )

        let firstTask = try #require(
            coordinator.open(firstFileURL, in: application)
        )
        let secondTask = try #require(
            coordinator.open(secondFileURL, in: application)
        )

        #expect(coordinator.isOpening)
        await firstTask.value
        await secondTask.value

        #expect(Set(openedFiles) == Set([firstFileURL, secondFileURL]))
        #expect(coordinator.isOpening == false)
    }
}
