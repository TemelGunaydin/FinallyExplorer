//
//  ContentView.swift
//  FinallyExplorer
//
//  Created by temel gunaydin on 14.11.2025.
//

import Foundation
import SwiftUI

// Klasorlere erisim hatasi icin kullanmak icin enum yapisi kurduk.
// LocalizedError protocolunu implement ediyoruz. Bu sayede errorDescription property'si olur ve error'u localize edebiliriz.
private enum DirectoryAccessError: LocalizedError {
    case invalidURL
    case permissionDenied(path: String, folderTitle: String)
    case notFound(path: String, folderTitle: String)
    case corrupt(path: String)
    case unknown(message: String, path: String, underlying: Error?)

    // Ornek : DirectoryAccessError.invalidURL.errorDescription yazarsak "Invalid directory URL" döner.
    // Ornek : DirectoryAccessError.permissionDenied(path: "~/Downloads", folderTitle: "Downloads").errorDescription yazarsak "Permission denied. Please check System Settings > Privacy & Security > Files and Folders to grant access to the Downloads folder.\n\nPath: ~/Downloads" döner.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid directory URL"
        case let .permissionDenied(path, folderTitle):
            return "Permission denied. Please check System Settings > Privacy & Security > Files and Folders to grant access to the \(folderTitle) folder.\n\nPath: \(path)"
        case let .notFound(path, folderTitle):
            return "The \(folderTitle) folder could not be found at this location.\n\nPath: \(path)"
        case let .corrupt(path):
            return "Unable to read the folder. It may be corrupted or inaccessible.\n\nPath: \(path)"
        case let .unknown(message, path, _):
            return "Unable to access folder: \(message)\n\nPath: \(path)"
        }
    }
}

private enum SidebarPlace: String, CaseIterable, Identifiable {
    case downloads
    case desktop
    case documents

    var title: String {
        switch self {
        case .downloads:
            "Downloads"

        case .desktop:
            "Desktop"

        case .documents:
            "Documents"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads:
            "folder"

        case .desktop:
            "folder"

        case .documents:
            "folder"
        }
    }

    // computed property olarak yarattik. SidebarPlace degerine gore url hesaplaniyor ve return ediliyor.
    var url: URL? {
        switch self {
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .documents:
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }

    var id: Self {
        self
    }
}

struct ContentView: View {
    @State private var selection: SidebarPlace? = .downloads
    var body: some View {
        NavigationSplitView {
            List(SidebarPlace.allCases, selection: $selection) { place in
                Label(place.title, systemImage: place.systemImage)
                    .tag(place)
            }.listStyle(.sidebar)
        } detail: {
            if let selection {
                // one way binding yapiyoruz. selection'in degeri degistiginde DestinationView'in place parametresi de degisir bu sebeple DestinationView'in task'i her seferinde calisir ve secili klasorun icerigi gosterilir.
                DestinationView(place: selection)
            } else {
                Text("Select a folder")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct DestinationView: View {
    let place: SidebarPlace
    @State private var directoryContents: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Simge ve klasor ismi gosteriliyor
            Label(place.title, systemImage: place.systemImage)
                .font(.title2.bold())

            // Dosya yolu gösteriliyor
            if let url = place.url {
                Text(url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Ustteki textin altinda bir adet cizgi ciziyoruz
                Divider()

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)

                            Text("Unable to Access Folder")
                                .font(.headline)

                            Text(errorMessage)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            if place == .desktop {
                                Text("To grant access:\n1. Open System Settings\n2. Go to Privacy & Security\n3. Select Files and Folders\n4. Find FinallyExplorer\n5. Enable Desktop Folder access")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if directoryContents.isEmpty {
                        Text("Folder is empty")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(directoryContents, id: \.self) { url in
                            FileRowView(url: url)
                        }
                    }
                }
            } else {
                Text("Folder unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task(id: place.id) {
            await loadDirectoryContents()
        }
    }

    // DestinationView'in task'i her seferinde çalışır. Yani secili klasorun icerigi gosteriyoruz. Async'dir. Bu sebeple yukleme yaparken once isLoading true olur ve en yukardaki isloading state oldugu icin progressView ekrana verilir.
    private func loadDirectoryContents() async {
        // place.url eger bir degere sahip degil ise else kismi calisir ve errorMessage state'ine DirectoryAccessError.invalidURL.localizedDescription atanir ve return ederiz.
        guard let url = place.url else {
            errorMessage = DirectoryAccessError.invalidURL.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let contents = try await fetchDirectoryContents(from: url, folderTitle: place.title)
            directoryContents = contents
            isLoading = false
        } catch let error as DirectoryAccessError {
            errorMessage = error.localizedDescription
            isLoading = false
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)\n\nPath: \(url.path)"
            isLoading = false
        }
    }
}

@MainActor
private struct FileRowView: View {
    let url: URL
    @State private var isDirectory: Bool = false
    @State private var fileSize: Int64?
    @State private var modificationDate: Date?

    var body: some View {
        HStack {
            Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(isDirectory ? .blue : .gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.body)

                if let fileSize = fileSize, !isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let modificationDate = modificationDate {
                    Text(modificationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .task {
            await loadFileAttributes()
        }
    }

    private func loadFileAttributes() async {
        do {
            let resourceValues = try await fetchFileAttributes(for: url)

            isDirectory = resourceValues.isDirectory ?? false
            fileSize = resourceValues.fileSize.map { Int64($0) }
            modificationDate = resourceValues.contentModificationDate
        } catch {
            // Handle error silently, use defaults
        }
    }
}

// Bunu async olmasinin sebebi Task.yield cagirmak icin yaptik yoksa fonksiyonun icinde olan ana islem senkron bir islemdir. Ama mainthread disinda yapmak istersek, cagrildigi yerde Task.detach icinde kullanmaliyiz.
private func fetchFileAttributes(for url: URL) async throws -> URLResourceValues {
    // Diger tasklar icin nefes alma imkani veriyoruz. Yani ui guncellemeleri yapilabilir demek. Kucuk bir hack gibi dusunuyorum.
    // Mevcut taski gecici olarak durdurduk dedik bu task ise view icinde .task {} ile yaratilan task'tir.
    await Task.yield()

    return try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
}

private func fetchDirectoryContents(from url: URL, folderTitle: String) async throws -> [URL] {
    // Yield to allow other tasks to run before blocking file system operations
    await Task.yield()

    // Resolve the URL to ensure it's fully expanded
    let resolvedURL = url.resolvingSymlinksInPath()

    // Try to read the directory contents directly
    // This will throw the actual error if there's a permission or access issue
    let contents: [URL]
    do {
        contents = try FileManager.default.contentsOfDirectory(
            at: resolvedURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    } catch let error as CocoaError {
        // Map CocoaError to our custom error type
        switch error.code {
        case .fileReadNoPermission:
            throw DirectoryAccessError.permissionDenied(path: resolvedURL.path, folderTitle: folderTitle)
        case .fileReadNoSuchFile:
            throw DirectoryAccessError.notFound(path: resolvedURL.path, folderTitle: folderTitle)
        case .fileReadCorruptFile:
            throw DirectoryAccessError.corrupt(path: resolvedURL.path)
        default:
            throw DirectoryAccessError.unknown(
                message: error.localizedDescription,
                path: resolvedURL.path,
                underlying: error
            )
        }
    } catch {
        throw DirectoryAccessError.unknown(
            message: error.localizedDescription,
            path: resolvedURL.path,
            underlying: error
        )
    }

    // Sort: directories first, then by name
    return try contents.sorted { url1, url2 in
        let resourceValues1 = try url1.resourceValues(forKeys: [.isDirectoryKey])
        let resourceValues2 = try url2.resourceValues(forKeys: [.isDirectoryKey])

        let isDir1 = resourceValues1.isDirectory ?? false
        let isDir2 = resourceValues2.isDirectory ?? false

        if isDir1 != isDir2 {
            return isDir1
        }

        return url1.lastPathComponent.localizedCaseInsensitiveCompare(url2.lastPathComponent) == .orderedAscending
    }
}

#Preview {
    ContentView()
}
