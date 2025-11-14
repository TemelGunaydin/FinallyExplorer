//
//  ContentView.swift
//  FinallyExplorer
//
//  Created by temel gunaydin on 14.11.2025.
//

import SwiftUI

private enum SidebarPlace: String, CaseIterable, Identifiable {
    case downloads
    case desktop

    var title: String {
        switch self {
        case .downloads:
            "Downloads"
        case .desktop:
            "Desktop"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads:
            "folder"
        case .desktop:
            "folder"
        }
    }

    var url: URL? {
        switch self {
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
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
                DestinationView(place: selection)
            } else {
                Text("Select a folder")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DestinationView: View {
    let place: SidebarPlace
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(place.title, systemImage: place.systemImage)
                .font(.title2.bold())

            if let url = place.url {
                Text(url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Folder unavailable")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
