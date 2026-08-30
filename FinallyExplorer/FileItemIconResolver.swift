//
//  FileItemIconResolver.swift
//  FinallyExplorer
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FileItemIconKind: Equatable, Sendable {
    case folder
    case image
    case pdf
    case video
    case audio
    case sourceCode
    case archive
    case spreadsheet
    case presentation
    case richTextDocument
    case book
    case font
    case diskImage
    case database
    case text
    case generic

    var customAssetName: String? {
        switch self {
        case .pdf:
            "PDFFileIcon"
        case .video:
            "VideoFileIcon"
        default:
            nil
        }
    }

    var systemName: String {
        switch self {
        case .folder:
            "folder.fill"
        case .image:
            "photo.fill"
        case .pdf:
            "doc.text.fill"
        case .video:
            "film.fill"
        case .audio:
            "waveform"
        case .sourceCode:
            "chevron.left.forwardslash.chevron.right"
        case .archive:
            "archivebox.fill"
        case .spreadsheet:
            "tablecells.fill"
        case .presentation:
            "rectangle.on.rectangle.angled"
        case .richTextDocument:
            "doc.richtext.fill"
        case .book:
            "book.closed.fill"
        case .font:
            "textformat"
        case .diskImage:
            "externaldrive.fill"
        case .database:
            "cylinder.fill"
        case .text:
            "doc.plaintext.fill"
        case .generic:
            "doc.fill"
        }
    }
}

nonisolated enum FileItemIconResolver {
    private static let videoExtensions: Set<String> = [
        "3gp", "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg",
        "mts", "m2ts", "ogv", "webm", "wmv",
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "flac", "m4a", "mp3", "ogg", "opus",
        "wav", "wma",
    ]
    private static let sourceCodeExtensions: Set<String> = [
        "asm", "bash", "c", "cc", "clj", "cpp", "cs", "css", "cxx", "dart", "ex",
        "exs", "fish", "go", "h", "hh", "hpp", "html", "java", "js", "jsx",
        "json", "kt", "kts", "lua", "m", "mm", "php", "pl", "py", "r", "rb",
        "rs", "scala", "scss", "sh", "sql", "svelte", "swift", "toml", "ts",
        "tsx", "vue", "xml", "yaml", "yml", "zsh",
    ]
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "cab", "gz", "rar", "tar", "tbz", "tbz2", "tgz",
        "txz", "xz", "zip", "zst",
    ]
    private static let spreadsheetExtensions: Set<String> = [
        "csv", "numbers", "ods", "tsv", "xls", "xlsm", "xlsx",
    ]
    private static let presentationExtensions: Set<String> = [
        "key", "odp", "pps", "ppsx", "ppt", "pptx",
    ]
    private static let richTextDocumentExtensions: Set<String> = [
        "doc", "docx", "odt", "pages", "rtf", "rtfd",
    ]
    private static let bookExtensions: Set<String> = [
        "azw", "azw3", "epub", "mobi",
    ]
    private static let fontExtensions: Set<String> = [
        "dfont", "otf", "ttc", "ttf", "woff", "woff2",
    ]
    private static let diskImageExtensions: Set<String> = [
        "dmg", "img", "iso", "sparsebundle", "sparseimage",
    ]
    private static let databaseExtensions: Set<String> = [
        "db", "realm", "sqlite", "sqlite3",
    ]

    static func kind(for item: FileItem) -> FileItemIconKind {
        if item.isDirectory {
            return .folder
        }
        if item.isImage {
            return .image
        }

        let fileExtension = item.url.pathExtension.lowercased()
        guard fileExtension.isEmpty == false else { return .generic }

        if fileExtension == "pdf" { return .pdf }
        if videoExtensions.contains(fileExtension) { return .video }
        if audioExtensions.contains(fileExtension) { return .audio }
        if sourceCodeExtensions.contains(fileExtension) { return .sourceCode }
        if archiveExtensions.contains(fileExtension) { return .archive }
        if spreadsheetExtensions.contains(fileExtension) { return .spreadsheet }
        if presentationExtensions.contains(fileExtension) { return .presentation }
        if richTextDocumentExtensions.contains(fileExtension) {
            return .richTextDocument
        }
        if bookExtensions.contains(fileExtension) { return .book }
        if fontExtensions.contains(fileExtension) { return .font }
        if diskImageExtensions.contains(fileExtension) { return .diskImage }
        if databaseExtensions.contains(fileExtension) { return .database }

        guard let contentType = UTType(filenameExtension: fileExtension) else {
            return .generic
        }
        if contentType.conforms(to: .image) { return .image }
        if contentType.conforms(to: .pdf) { return .pdf }
        if contentType.conforms(to: .movie) { return .video }
        if contentType.conforms(to: .audio) { return .audio }
        if contentType.conforms(to: .sourceCode) { return .sourceCode }
        if contentType.conforms(to: .text) { return .text }
        return .generic
    }
}

struct FileItemIconView: View {
    let item: FileItem

    private var kind: FileItemIconKind {
        FileItemIconResolver.kind(for: item)
    }

    var body: some View {
        icon
            .frame(
                width: ExplorerTheme.rowIconFrameSize,
                height: ExplorerTheme.rowIconFrameSize
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let customAssetName = kind.customAssetName {
            Image(customAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 29, height: 29)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: kind.systemName)
                .font(
                    .system(
                        size: kind == .folder
                            ? ExplorerTheme.folderRowIconSize
                            : ExplorerTheme.fileRowIconSize,
                        weight: .medium
                    )
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch kind {
        case .folder:
            ExplorerTheme.folderIcon
        case .image:
            ExplorerTheme.imageIcon
        case .pdf:
            ExplorerTheme.pdfIcon
        case .video:
            ExplorerTheme.videoIcon
        case .audio:
            ExplorerTheme.audioIcon
        case .sourceCode:
            ExplorerTheme.codeIcon
        case .archive, .diskImage:
            ExplorerTheme.archiveIcon
        case .spreadsheet:
            ExplorerTheme.spreadsheetIcon
        case .presentation:
            ExplorerTheme.presentationIcon
        case .richTextDocument, .book, .font, .database, .text, .generic:
            ExplorerTheme.documentIcon
        }
    }
}
