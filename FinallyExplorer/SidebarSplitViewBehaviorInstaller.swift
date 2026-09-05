//
//  SidebarSplitViewBehaviorInstaller.swift
//  FinallyExplorer
//

import SwiftUI

struct SidebarSplitViewBehaviorInstaller: NSViewRepresentable {
    static let minimumWidth: CGFloat = 210
    static let idealWidth: CGFloat = 232
    static let maximumWidth: CGFloat = 280

    var isSidebarVisible = true

    func makeNSView(context: Context) -> SidebarSplitViewAttachmentView {
        let view = SidebarSplitViewAttachmentView(
            minimumThickness: Self.minimumWidth,
            maximumThickness: Self.maximumWidth
        )
        view.isSidebarVisible = isSidebarVisible
        return view
    }

    func updateNSView(
        _ nsView: SidebarSplitViewAttachmentView,
        context: Context
    ) {
        nsView.isSidebarVisible = isSidebarVisible
        nsView.scheduleConfiguration()
    }

    static func dismantleNSView(_ nsView: SidebarSplitViewAttachmentView, coordinator: ()) {
        nsView.detach()
    }
}
