//
//  ExplorerWindowTrafficControlsInstaller.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerWindowTrafficControlsInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> ExplorerWindowAttachmentView {
        ExplorerWindowAttachmentView()
    }

    func updateNSView(
        _ nsView: ExplorerWindowAttachmentView,
        context: Context
    ) {
        nsView.installIfNeeded()
    }

    static func dismantleNSView(
        _ nsView: ExplorerWindowAttachmentView,
        coordinator: ()
    ) {
        nsView.uninstall()
    }
}
