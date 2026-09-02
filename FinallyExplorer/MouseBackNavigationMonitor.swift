//
//  MouseBackNavigationMonitor.swift
//  FinallyExplorer
//

import SwiftUI

struct MouseBackNavigationMonitor: NSViewRepresentable {
    let navigateBack: () -> Bool

    func makeNSView(context: Context) -> MouseBackNavigationAttachmentView {
        MouseBackNavigationAttachmentView(navigateBack: navigateBack)
    }

    func updateNSView(
        _ nsView: MouseBackNavigationAttachmentView,
        context: Context
    ) {
        nsView.update(navigateBack: navigateBack)
    }

    static func dismantleNSView(
        _ nsView: MouseBackNavigationAttachmentView,
        coordinator: ()
    ) {
        nsView.uninstall()
    }
}
