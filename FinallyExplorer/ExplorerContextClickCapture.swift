//
//  ExplorerContextClickCapture.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerContextClickCapture: NSViewRepresentable {
    let onContextClick: (UnitPoint) -> Void

    func makeNSView(context: Context) -> ExplorerContextClickCaptureView {
        let view = ExplorerContextClickCaptureView()
        view.onContextClick = onContextClick
        return view
    }

    func updateNSView(
        _ view: ExplorerContextClickCaptureView,
        context: Context
    ) {
        view.onContextClick = onContextClick
    }
}
