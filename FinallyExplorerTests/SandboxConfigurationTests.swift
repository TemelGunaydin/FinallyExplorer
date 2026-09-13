import Foundation
import Security
import Testing
@testable import FinallyExplorer

struct SandboxConfigurationTests {
    @Test("Container migration names only this app's offline catalog store")
    func migrationManifest() throws {
        let url = try #require(Bundle.main.url(forResource: "container-migration", withExtension: "plist"))
        let values = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(Set(values.keys) == ["Move"])
        #expect(values["Move"] as? [String] == ["${ApplicationSupport}/FinallyExplorer/OfflineCatalogs"])
    }

    @Test("The running test host has the app's sandbox and explicit folder grant entitlements")
    func runtimeEntitlements() throws {
        let task = try #require(SecTaskCreateFromSelf(nil))
        for key in ["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write",
                    "com.apple.security.files.bookmarks.app-scope", "com.apple.security.files.downloads.read-write"] {
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? Bool
            #expect(value == true, "Missing runtime entitlement: \(key)")
        }
        // XCTest adds its own read-only/testmanager exceptions. This check does
        // not substitute for inspecting a non-test Release artifact or testing
        // native Powerbox grants in a fresh launch.
    }

    @Test("Standard user folders remain outside the sandbox container")
    func namedUserFolders() {
        for name in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies"] {
            let url = UserHomeDirectory.standardFolder(name)
            #expect(url.deletingLastPathComponent() == UserHomeDirectory.url)
            #expect(url.lastPathComponent == name)
            #expect(!url.path.contains("/Library/Containers/"))
        }
    }
}
