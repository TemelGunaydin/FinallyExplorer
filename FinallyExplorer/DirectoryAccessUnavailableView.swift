//
//  DirectoryAccessUnavailableView.swift
//  FinallyExplorer
//

import SwiftUI

struct DirectoryAccessUnavailableView: View {
    let error: DirectoryAccessError
    let openPrivacySettings: () -> Void

    @ViewBuilder
    var body: some View {
        switch error {
        case let .permissionDenied(_, folderTitle):
            ContentUnavailableView {
                Label(
                    "\(folderTitle) Access Needed",
                    systemImage: "lock.fill"
                )
            } description: {
                Text("Allow FinallyExplorer to view this folder.")
            } actions: {
                Button(action: openPrivacySettings) {
                    Label(
                        "Open Privacy Settings",
                        systemImage: "gearshape.fill"
                    )
                }
                .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                .accessibilityIdentifier("open-folder-privacy-settings")
            }

        default:
            ContentUnavailableView(
                "Unable to Access Folder",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(error.localizedDescription)
            )
        }
    }
}
