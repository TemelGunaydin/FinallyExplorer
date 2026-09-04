//
//  OpenWithApplicationSection.swift
//  FinallyExplorer
//

import Foundation
import SwiftUI

struct OpenWithApplicationSection: View {
    @Environment(FileOpenApplicationCoordinator.self) private var fileOpenApplications
    @Environment(\.explorerTheme) private var theme

    let fileURL: URL
    let onOpen: (FileOpenApplication) -> Void

    @State private var isMenuPresented = false

    var body: some View {
        Button(action: presentMenu) {
            HStack(spacing: 9) {
                Image(systemName: "app.badge")
                    .frame(width: 18)

                Text("Open With")

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .explorerContextMenuRow()
        .accessibilityLabel("Open With")
        .accessibilityValue(isMenuPresented ? "Open" : "Closed")
        .popover(
            isPresented: $isMenuPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .leading
        ) {
            applicationMenu
                .environment(\.explorerTheme, theme)
        }
    }

    @ViewBuilder
    private var applicationMenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if fileOpenApplications.hasLoadedApplications(for: fileURL) {
                    let applications = fileOpenApplications.applications(for: fileURL)

                    if applications.isEmpty {
                        ExplorerContextMenuActionButton(
                            title: "No Compatible Applications",
                            systemImage: "app.badge",
                            isEnabled: false
                        ) {}
                    } else {
                        ForEach(applications) { application in
                            OpenWithApplicationContextButton(
                                application: application,
                                isEnabled: fileOpenApplications.isOpening == false
                            ) {
                                choose(application)
                            }
                        }
                    }
                } else {
                    ExplorerContextMenuActionButton(
                        title: "Finding Compatible Applications…",
                        systemImage: "app.badge",
                        isEnabled: false
                    ) {}
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .frame(width: 286)
        .frame(maxHeight: 420)
        .background(theme.elevatedPanel)
        .presentationBackground(theme.elevatedPanel)
        .presentationCornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Compatible Applications")
        .accessibilityIdentifier("open-with-application-menu")
    }

    private func presentMenu() {
        isMenuPresented = true
    }

    private func choose(_ application: FileOpenApplication) {
        isMenuPresented = false

        Task { @MainActor in
            await Task.yield()
            onOpen(application)
        }
    }
}
