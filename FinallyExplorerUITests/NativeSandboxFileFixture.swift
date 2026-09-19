#if FINALLY_EXPLORER_NATIVE_SANDBOX_ACCEPTANCE
import XCTest

/// Prepared outside the runner; the runner may read but cannot write /private/tmp.
struct NativeSandboxFileFixture {
    static let needleName = "FENativeNeedle.json"
    static let needleText = "{\"message\":\"Synthetic native-token-7319\",\"count\":19}\n"
    static let controlText = "Synthetic control document without the search token.\n"
    static let markerText = "Synthetic native Sandbox file-consumer fixture.\n"
    let root: URL

    init(path: String) throws {
        let candidate = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let isTemporaryRoot = parent.pathComponents == ["/", "private", "tmp"]
            || parent.pathComponents == ["/", "tmp"]
        guard isTemporaryRoot,
              candidate.lastPathComponent.hasPrefix("fe-native-f") else {
            throw NSError(domain: "NativeSandboxFileFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing a broad or non-file-QA fixture path: \(candidate.path); parent: \(parent.pathComponents)."
            ])
        }
        root = candidate
        for folder in [root, root.appending(path: "QA Source"), root.appending(path: "QA Destination")] {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isDirectory, true)
            XCTAssertEqual(values.isSymbolicLink, false)
        }
    }

    func assertOriginalsUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
        for (path, content) in [
            ("SandboxMarker.txt", Self.markerText),
            ("QA Source/\(Self.needleName)", Self.needleText),
            ("QA Source/Control.txt", Self.controlText)
        ] {
            let url = root.appending(path: path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isRegularFile, true, file: file, line: line)
            XCTAssertEqual(values.isSymbolicLink, false, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: url), Data(content.utf8), file: file, line: line)
        }
    }
}
#endif
