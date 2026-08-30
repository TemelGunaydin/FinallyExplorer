//
//  FileItemIconResolverTests.swift
//  FinallyExplorerTests
//

import AppKit
import Foundation
import Testing
@testable import FinallyExplorer

struct FileItemIconResolverTests {
    @Test("Common media, document, archive, and code extensions get distinct icons")
    func commonFileTypesResolveToMeaningfulKinds() {
        let expectations: [(String, FileItemIconKind)] = [
            ("manual.PDF", .pdf),
            ("feature.mkv", .video),
            ("clip.MP4", .video),
            ("recording.flac", .audio),
            ("App.swift", .sourceCode),
            ("engine.cpp", .sourceCode),
            ("header.HPP", .sourceCode),
            ("service.ts", .sourceCode),
            ("site.tsx", .sourceCode),
            ("backup.7z", .archive),
            ("budget.xlsx", .spreadsheet),
            ("pitch.key", .presentation),
            ("novel.epub", .book),
            ("catalog.sqlite", .database),
            ("notes.txt", .text),
        ]

        for (name, expectedKind) in expectations {
            #expect(FileItemIconResolver.kind(for: item(named: name)) == expectedKind)
        }
    }

    @Test("Folder and image metadata take precedence over misleading extensions")
    func metadataTakesPrecedenceOverExtension() {
        #expect(
            FileItemIconResolver.kind(
                for: item(named: "Videos.mkv", isDirectory: true)
            ) == .folder
        )
        #expect(
            FileItemIconResolver.kind(
                for: item(named: "preview.unknown", isImage: true)
            ) == .image
        )
    }

    @Test("Missing and unknown extensions use the stable generic fallback")
    func malformedAndUnknownNamesUseGenericFallback() {
        for name in ["README", ".gitignore", "payload.not-a-real-file-type"] {
            #expect(FileItemIconResolver.kind(for: item(named: name)) == .generic)
        }
    }

    @Test("Every icon kind maps to a nonempty SF Symbol name")
    func everyKindHasASymbol() {
        let kinds: [FileItemIconKind] = [
            .folder, .image, .pdf, .video, .audio, .sourceCode, .archive,
            .spreadsheet, .presentation, .richTextDocument, .book, .font,
            .diskImage, .database, .text, .generic,
        ]

        for kind in kinds {
            #expect(kind.systemName.isEmpty == false)
            #expect(
                NSImage(
                    systemSymbolName: kind.systemName,
                    accessibilityDescription: nil
                ) != nil
            )
        }
    }

    @Test("PDF and video kinds use the generated production assets")
    func generatedAssetMapping() {
        #expect(FileItemIconKind.pdf.customAssetName == "PDFFileIcon")
        #expect(FileItemIconKind.video.customAssetName == "VideoFileIcon")
        #expect(FileItemIconKind.folder.customAssetName == nil)
        #expect(FileItemIconKind.sourceCode.customAssetName == nil)
    }

    private func item(
        named name: String,
        isDirectory: Bool = false,
        isImage: Bool = false
    ) -> FileItem {
        FileItem(
            url: URL(filePath: "/tmp").appending(path: name),
            isDirectory: isDirectory,
            isImage: isImage,
            fileSize: 0,
            modificationDate: nil
        )
    }
}
