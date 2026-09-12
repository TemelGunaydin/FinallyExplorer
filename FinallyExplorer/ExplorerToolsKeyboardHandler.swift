import SwiftUI

struct ExplorerToolsKeyboardHandler: NSViewRepresentable {
    let onMove: (Int) -> Void
    let onActivate: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> ExplorerToolsKeyboardAttachmentView {
        ExplorerToolsKeyboardAttachmentView(onMove: onMove, onActivate: onActivate, onClose: onClose)
    }

    func updateNSView(_ view: ExplorerToolsKeyboardAttachmentView, context: Context) {
        view.update(onMove: onMove, onActivate: onActivate, onClose: onClose)
    }

    static func dismantleNSView(_ view: ExplorerToolsKeyboardAttachmentView, coordinator: ()) {
        view.uninstall()
    }
}
