import Foundation

nonisolated enum ExplorerLegalDocument: String, CaseIterable, Identifiable, Sendable {
    case privacy
    case terms
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms of Service"
        case .licenses: "Open-Source Licenses"
        }
    }

    var systemImage: String {
        switch self {
        case .privacy: "hand.raised"
        case .terms: "doc.text"
        case .licenses: "curlybraces"
        }
    }

    func loadText(from bundle: Bundle = .main) throws -> String {
        switch self {
        case .privacy:
            try Self.readResource("PrivacyPolicy", extension: "md", directory: "Legal", bundle: bundle)
        case .terms:
            try Self.readResource("TermsOfService", extension: "md", directory: "Legal", bundle: bundle)
        case .licenses:
            try "## FFF — fast file search\n\n"
                + Self.readResource("FFF-LICENSE", extension: "txt", directory: "ThirdPartyNotices", bundle: bundle)
                + "\n\n## Devicon — developer file icons\n\n"
                + Self.readResource("Devicon-LICENSE", extension: "txt", directory: "ThirdPartyNotices", bundle: bundle)
        }
    }

    private static func readResource(
        _ name: String, extension fileExtension: String, directory: String, bundle: Bundle
    ) throws -> String {
        // Xcode's synchronized resource groups may flatten the bundle paths.
        guard let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: directory)
            ?? bundle.url(forResource: name, withExtension: fileExtension) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
