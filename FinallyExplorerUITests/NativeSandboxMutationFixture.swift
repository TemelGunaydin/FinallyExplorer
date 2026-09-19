#if FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE
import XCTest

/// Prepared outside XCTest. The runner only validates bytes; all mutations
/// must be performed through the separately signed, normally launched QA app.
struct NativeSandboxMutationFixture {
    static let copyText = "Synthetic copy payload 7319. Original must remain unchanged.\n"
    static let noteText = "Synthetic ZIP payload — Unicode 7319.\n"
    static let hiddenText = "Synthetic hidden ZIP payload 7319.\n"
    static let markerText = "Synthetic native Sandbox mutation fixture 20260919.\n"
    static let anchorText = "Synthetic destination anchor. Do not modify.\n"
    let root: URL
    var source: URL { root.appending(path: "Source") }
    var destination: URL { root.appending(path: "Destination") }

    init(path: String) throws {
        let url = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
        guard (parent == ["/", "private", "tmp"] || parent == ["/", "tmp"]),
              url.lastPathComponent.hasPrefix("fe-native-m") else {
            throw NSError(domain: "NativeSandboxMutationFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing a broad or non-mutation-QA fixture path."
            ])
        }
        root = url
        for directory in [root, source, destination, source.appending(path: "Package"), source.appending(path: "Package/Notes")] {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isDirectory, true)
            XCTAssertEqual(values.isSymbolicLink, false)
        }
        try assertOriginalsUnchanged()
        // A failed run is retained as evidence, never reset or overwritten.
        XCTAssertEqual(try children(root), ["Destination", "SandboxMarker.txt", "Source"])
        XCTAssertEqual(try children(source), ["FECopy.txt", "Package"])
        XCTAssertEqual(try children(destination), ["Anchor.txt"])
        XCTAssertEqual(try children(source.appending(path: "Package")), [".hidden", "Notes"])
        XCTAssertEqual(try children(source.appending(path: "Package/Notes")), ["Résumé.txt"])
    }

    func assertOriginalsUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
        for (path, content) in [
            ("SandboxMarker.txt", Self.markerText), ("Source/FECopy.txt", Self.copyText),
            ("Source/Package/Notes/Résumé.txt", Self.noteText), ("Source/Package/.hidden", Self.hiddenText),
            ("Destination/Anchor.txt", Self.anchorText)
        ] {
            try assertText(content, at: root.appending(path: path), file: file, line: line)
        }
    }

    func assertText(_ text: String, at url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        XCTAssertEqual(values.isRegularFile, true, file: file, line: line)
        XCTAssertEqual(values.isSymbolicLink, false, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: url), Data(text.utf8), file: file, line: line)
    }

    func children(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func assertArchive(_ name: String, contains entries: [String: String],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let archive = source.appending(path: name)
        let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        XCTAssertEqual(values.isRegularFile, true, file: file, line: line)
        XCTAssertEqual(values.isSymbolicLink, false, file: file, line: line)
        XCTAssertLessThan(try XCTUnwrap(values.fileSize), 1_000_000, file: file, line: line)
        _ = try unzip(["-t", archive.path])
        let listing = String(decoding: try unzip(["-Z1", archive.path]), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        // Finder-style metadata/directories are allowed; every payload must be
        // named explicitly and have exact original bytes. No extraction occurs.
        let payloads = listing.filter { $0.hasSuffix("/") == false && $0.hasPrefix("__MACOSX/") == false }
        XCTAssertEqual(Set(payloads), Set(entries.keys), file: file, line: line)
        for (entry, text) in entries {
            XCTAssertEqual(try unzip(["-p", archive.path, entry]), Data(text.utf8), file: file, line: line)
        }
    }

    private func unzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = arguments
        // XCTest can launch with the C locale. macOS unzip then renders each
        // non-ASCII filename byte as '?' even when the ZIP name is intact.
        // Pin only this read-only verifier, not the QA app or user's locale.
        process.environment = ["LC_ALL": "en_US.UTF-8"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        try output.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        return data
    }
}
#endif
