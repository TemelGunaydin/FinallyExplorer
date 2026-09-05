//
//  SystemPrivacySettingsOpener.swift
//  FinallyExplorer
//

import AppKit

@MainActor
enum SystemPrivacySettingsOpener {
    static func openAppleIntelligence() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        openSystemSettings()
    }

    static func openFilesAndFolders() {
        guard let filesAndFoldersURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        ) else {
            openSystemSettings()
            return
        }

        guard NSWorkspace.shared.open(filesAndFoldersURL) == false else {
            return
        }

        openSystemSettings()
    }

    private static func openSystemSettings() {
        guard let settingsURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: settingsURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
