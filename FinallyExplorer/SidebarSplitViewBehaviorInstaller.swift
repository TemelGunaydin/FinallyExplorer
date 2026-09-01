//
//  SidebarSplitViewBehaviorInstaller.swift
//  FinallyExplorer
//

import SwiftUI

struct SidebarSplitViewBehaviorInstaller: NSViewRepresentable {
    static let minimumWidth: CGFloat = 210
    static let idealWidth: CGFloat = 232
    static let maximumWidth: CGFloat = 280

    func makeNSView(context: Context) -> SidebarSplitViewAttachmentView {
        SidebarSplitViewAttachmentView(
            minimumThickness: Self.minimumWidth,
            maximumThickness: Self.maximumWidth
        )
    }

    func updateNSView(
        _ nsView: SidebarSplitViewAttachmentView,
        context: Context
    ) {
        nsView.scheduleConfiguration()
    }
}
