import Foundation
import Testing
@testable import FinallyExplorer

struct TextFilePreviewServiceTests {
    @Test("Source and JSON files expose their literal contents", arguments: ["swift", "json", "py", "ts", "md"])
    func readsDeveloperFiles(_ fileExtension: String) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Preview-\(UUID()).\(fileExtension)")
        let contents = "{\"message\": \"Hello 👋\", \"count\": 42}\n"
        try Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = FileItem(url: url, isDirectory: false, isImage: false,
                            fileSize: nil, modificationDate: nil)

        #expect(TextFilePreviewService.supports(item))
        let preview = try await TextFilePreviewService().load(url)
        #expect(preview.text == contents)
        #expect(preview.isTruncated == false)
    }

    @Test("Large previews are bounded without splitting Unicode")
    func truncatesWithoutCorruptingUnicode() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Preview-\(UUID()).json")
        let prefix = String(repeating: "a", count: TextFilePreviewService.maximumByteCount - 1)
        try Data((prefix + "👋more").utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await TextFilePreviewService().load(url)
        #expect(preview.text == prefix)
        #expect(preview.isTruncated)
    }

    @Test("UTF-16 and empty files are readable", arguments: [false, true])
    func readsUTF16AndEmptyFiles(isEmpty: Bool) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Preview-\(UUID()).txt")
        let text = isEmpty ? "" : "Hello 👋\nSecond line"
        let data = isEmpty ? Data() : Data([0xFF, 0xFE]) + Data(text.utf16.flatMap {
            [UInt8($0 & 0xFF), UInt8($0 >> 8)]
        })
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await TextFilePreviewService().load(url).text == text)
    }

    @Test("Binary data masquerading as code produces an error")
    func rejectsBinaryContents() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Preview-\(UUID()).swift")
        try Data([0x7F, 0x00, 0xFE, 0x10]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: TextFilePreviewError.notText) {
            try await TextFilePreviewService().load(url)
        }
    }
}
