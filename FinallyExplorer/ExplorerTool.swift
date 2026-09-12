import Foundation

enum ExplorerTool: String, CaseIterable, Identifiable {
    case visualSearch, documents, duplicates, organize, offlineCatalogs
    var id: Self { self }
    var requiresFolder: Bool { self == .duplicates || self == .organize }
    var title: String {
        switch self {
        case .visualSearch: "Visual Search"
        case .documents: "Ask Documents"
        case .duplicates: "Find Duplicates"
        case .organize: "Organize Folder"
        case .offlineCatalogs: "Offline Catalogs"
        }
    }
    var detail: String {
        switch self {
        case .visualSearch: "Find scenes and text in photos."
        case .documents: "Get answers with source quotes."
        case .duplicates: "Review identical copies before removing."
        case .organize: "Preview how your files will be grouped."
        case .offlineCatalogs: "Search saved disk listings, even offline."
        }
    }
    var systemImage: String {
        switch self {
        case .visualSearch: "photo.badge.magnifyingglass"
        case .documents: "text.bubble"
        case .duplicates: "doc.on.doc"
        case .organize: "folder.badge.gearshape"
        case .offlineCatalogs: "externaldrive"
        }
    }
    var accessibilityID: String {
        switch self {
        case .visualSearch: "file-tools-visual-search"
        case .documents: "file-tools-documents"
        case .duplicates: "file-tools-duplicates"
        case .organize: "file-tools-organize"
        case .offlineCatalogs: "file-tools-offline-catalogs"
        }
    }
}
