import Foundation
import CryptoKit
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

    @Test("Bundled FFF license matches the audited vendored license digest")
    func fffNoticeMatchesVendor() throws {
        let url = try #require(Bundle.main.url(forResource: "FFF-LICENSE", withExtension: "txt", subdirectory: "ThirdPartyNotices")
            ?? Bundle.main.url(forResource: "FFF-LICENSE", withExtension: "txt"))
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // SHA-256 of Vendor/FFF/LICENSE. Testing the bundled copy avoids granting
        // the sandboxed app access to the developer's entire source repository.
        #expect(digest == "f8264de82db188834a5711d7e348dc08c33db14f79bb587ccb42616fd694ee81")
        let original = String(decoding: data, as: UTF8.self)
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
