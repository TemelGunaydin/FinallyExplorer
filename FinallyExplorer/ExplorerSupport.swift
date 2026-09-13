import Foundation

nonisolated enum ExplorerSupport {
    static let email = "support@buildandruns.com"

    static var emailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "FinallyExplorer support")]
        return components.url
    }
}
