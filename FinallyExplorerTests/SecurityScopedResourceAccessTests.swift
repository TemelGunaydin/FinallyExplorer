import Foundation
import Synchronization
import Testing
@testable import FinallyExplorer

struct SecurityScopedResourceAccessTests {
    @Test("An explicit lease stops only successfully started local resources, once each")
    func balancedExplicitScopes() throws {
        let allowed = URL(filePath: "/selected/Report.txt")
        let rejected = URL(filePath: "/selected/Denied.txt")
        let remote = try #require(URL(string: "https://example.com/Report.txt"))
        let started = Mutex<[URL]>([])
        let stopped = Mutex<[URL]>([])
        var lease: SecurityScopedResourceAccess? = SecurityScopedResourceAccess(
            starting: [allowed, allowed, rejected, remote],
            start: { url in started.withLock { $0.append(url) }; return url == allowed },
            stop: { url in stopped.withLock { $0.append(url) } }
        )
        #expect(started.withLock { $0 } == [allowed, rejected])
        #expect(stopped.withLock { $0.isEmpty })
        withExtendedLifetime(lease) {}
        lease = nil
        #expect(stopped.withLock { $0 } == [allowed])
    }

    @Test("A panel lease adopts implicit access and releases it when the final owner ends")
    func sharedPanelLease() {
        let file = URL(filePath: "/selected/Report.txt")
        let stopped = Mutex<[URL]>([])
        var first: SecurityScopedResourceAccess? = SecurityScopedResourceAccess(adoptingPanelURLs: [file]) {
            url in stopped.withLock { $0.append(url) }
        }
        var second = first
        first = nil
        #expect(stopped.withLock { $0.isEmpty })
        withExtendedLifetime(second) {}
        second = nil
        #expect(stopped.withLock { $0 } == [file])
    }
}
