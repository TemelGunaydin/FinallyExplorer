import Foundation

nonisolated protocol FolderOrganizationPlanning: Sendable {
    func preview(rootURL: URL, rule: FolderOrganizationRule, includesHidden: Bool,
                 progress: @escaping @Sendable (FolderWorkProgress) async -> Void) async throws -> FolderOrganizationPlan
}

nonisolated struct FolderOrganizationService: FolderOrganizationPlanning {
    var calendar = Calendar.current
    var entryLimit = 50_000

    @concurrent
    func preview(
        rootURL: URL, rule: FolderOrganizationRule, includesHidden: Bool = false,
        progress: @escaping @Sendable (FolderWorkProgress) async -> Void = { _ in }
    ) async throws -> FolderOrganizationPlan {
        try Task.checkCancellation()
        let url = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path != "/", (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else {
            throw FileToolsError.invalidFolder
        }
        let root = try ScopedFolderDescriptor(rootURL: url)
        let state = try root.state()
        let (entries, excluded) = try await FolderTreeScanner.scan(
            root, rootURL: url, includesHidden: includesHidden, entryLimit: entryLimit, recursive: false, progress: progress
        )
        var proposed: [FolderOrganizationRow] = [], skipped: [FolderOrganizationRow] = []
        for entry in entries.values.sorted(by: { $0.relativePath < $1.relativePath }) {
            try Task.checkCancellation()
            let reason = entry.skippedReason ?? (entry.state.isDirectory ? "Folder — contents left in place" : nil)
            if let reason {
                skipped.append(FolderOrganizationRow(sourcePath: entry.relativePath, destinationPath: nil, skippedReason: reason))
                continue
            }
            let folder = destinationFolder(for: entry, rootURL: url, rule: rule)
            let target = "\(folder)/\(entry.relativePath)"
            var conflict: String?
            if let existing = try root.state(of: folder) {
                if existing.isDirectory == false || existing.isPlaceholder || existing.device != state.device {
                    conflict = "Destination folder is a link, special item, cloud placeholder or mounted folder"
                } else {
                    let parent = try root.directory([folder])
                    if try parent.state(of: entry.relativePath) != nil { conflict = "Destination already exists — never overwrite" }
                }
            }
            let row = FolderOrganizationRow(sourcePath: entry.relativePath, destinationPath: target, skippedReason: conflict)
            if conflict == nil { proposed.append(row) } else { skipped.append(row) }
        }
        try FolderTreeScanner.validate(root, root: state, entries: entries)
        guard try ScopedFolderDescriptor(rootURL: url).state().hasSameIdentity(as: state) else { throw FileToolsError.scanAgain(url.path) }
        return FolderOrganizationPlan(rootURL: url, rule: rule, proposed: proposed, skipped: skipped, excludedHiddenCount: excluded)
    }

    private func destinationFolder(for entry: ComparedFolderEntry, rootURL: URL, rule: FolderOrganizationRule) -> String {
        if rule == .modifiedMonth {
            let components = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(entry.state.modifiedSeconds)))
            guard let year = components.year, let month = components.month else { return "Unknown Date" }
            return String(format: "%04d-%02d", year, month)
        }
        let item = FileItem(url: rootURL.appending(path: entry.relativePath), isDirectory: false, isImage: false,
                            fileSize: entry.state.size, modificationDate: nil)
        return switch FileItemIconResolver.kind(for: item) {
        case .image: "Images"
        case .video: "Videos"
        case .audio: "Audio"
        case .sourceCode: "Code"
        case .archive: "Archives"
        case .spreadsheet: "Spreadsheets"
        case .presentation: "Presentations"
        case .pdf, .richTextDocument, .text: "Documents"
        case .book: "Books"
        case .font: "Fonts"
        case .diskImage: "Disk Images"
        case .database: "Databases"
        case .folder, .generic: "Other"
        }
    }
}
