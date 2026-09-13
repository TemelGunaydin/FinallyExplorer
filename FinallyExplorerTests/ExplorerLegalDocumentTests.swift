import Foundation
import Testing
@testable import FinallyExplorer

struct ExplorerLegalDocumentTests {
    @Test("Every legal document is bundled, readable offline, and has stable sections", arguments: ExplorerLegalDocument.allCases)
    func bundledDocuments(_ document: ExplorerLegalDocument) throws {
        let text = try document.loadText()
        #expect(text.count > 500)
        let blocks = ExplorerLegalBlock.parse(text)
        #expect(blocks.isEmpty == false)
        #expect(blocks.contains { $0.isHeading })
        #expect(Set(blocks.map(\.id)).count == blocks.count)
        #expect(blocks.allSatisfy { $0.text.isEmpty == false })
    }

    @Test("Policies disclose persistence, permission limits, and draft status")
    func privacyDisclosures() throws {
        let text = try ExplorerLegalDocument.privacy.loadText()
        for required in ["Pre-release", "Closing a tool panel alone", "Offline Catalogs", "does not bypass denied permissions",
                         "Hosting-provider identity", "support@buildandruns.com"] {
            #expect(text.contains(required), "Missing disclosure: \(required)")
        }
        #expect(text.contains("https://buildandruns.com/finallyexplorer") == false,
                "Do not link to the product website before it has been published and verified.")
    }

    @Test("Bundled FFF license matches the vendored license byte for byte")
    func fffNoticeMatchesVendor() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let original = try String(contentsOf: root.appending(path: "Vendor/FFF/LICENSE"), encoding: .utf8)
        let notices = try ExplorerLegalDocument.licenses.loadText()
        #expect(notices.contains(original))
        #expect(notices.contains("Copyright (c) 2015 konpa"))
    }

    @Test("Small legal reader handles blank paragraphs, CRLF, headings, and links")
    func documentBlocks() {
        let blocks = ExplorerLegalBlock.parse("\r\n## Heading\r\n\r\nA [link](https://www.apple.com/legal/privacy/).\r\n\r\n\r\n\r\nNext paragraph.\r\n")
        #expect(blocks.count == 3)
        #expect(blocks.map(\.id) == [0, 1, 2])
        #expect(blocks.first?.text == "Heading")
        #expect(blocks.first?.isHeading == true)
        #expect(blocks.dropFirst().allSatisfy { $0.isHeading == false })
        #expect(ExplorerLegalBlock.parse("  \n\n").isEmpty)
    }

    @Test("Support email contains a subject but no files, diagnostics, or message body")
    func supportURL() throws {
        let url = try #require(ExplorerSupport.emailURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == ExplorerSupport.email)
        #expect(components.queryItems == [URLQueryItem(name: "subject", value: "FinallyExplorer support")])
    }

    @Test("The built app declares its category, copyright, and Downloads purpose")
    func appMetadata() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.utilities")
        #expect((info["NSHumanReadableCopyright"] as? String)?.contains("Temel Gunaydin") == true)
        #expect((info["NSDownloadsFolderUsageDescription"] as? String)?.isEmpty == false)
    }
}
