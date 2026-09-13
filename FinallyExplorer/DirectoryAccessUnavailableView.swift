//
//  DirectoryAccessUnavailableView.swift
//  FinallyExplorer
//

import SwiftUI

struct DirectoryAccessUnavailableView: View {
    let error: DirectoryAccessError
    let openPrivacySettings: () -> Void
    var chooseFolder: (() -> Void)? = nil
    var retry: (() -> Void)? = nil
    var isChoosing = false
    var selectionError: String? = nil

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
                Text("Choose this folder to allow access. If macOS still blocks it, check Privacy Settings.")
                if let selectionError { Text(selectionError) }
            } actions: {
                folderActions
                Button(action: openPrivacySettings) {
                    Label(
                        "Open Privacy Settings",
                        systemImage: "gearshape.fill"
                    )
                }
                .buttonStyle(ExplorerDialogButtonStyle())
                .accessibilityIdentifier("open-folder-privacy-settings")
            }

        default:
            ContentUnavailableView {
                Label("Unable to Access Folder", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(error.localizedDescription)
                if let selectionError { Text(selectionError) }
            } actions: {
                folderActions
            }
        }
    }

    @ViewBuilder
    private var folderActions: some View {
        if let chooseFolder {
            Button(isChoosing ? "Choosing Folder…" : "Choose Folder…", systemImage: "folder", action: chooseFolder)
                .buttonStyle(ExplorerPanePrimaryButtonStyle(isCompact: false))
                .disabled(isChoosing)
                .accessibilityIdentifier("allow-folder-access")
        }
        if let retry {
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(ExplorerDialogButtonStyle())
                .disabled(isChoosing)
                .accessibilityIdentifier("retry-folder-access")
        }
    }
}
