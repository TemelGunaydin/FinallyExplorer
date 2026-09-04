//
//  ExplorerContextClickCaptureView.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

@MainActor
final class ExplorerContextClickCaptureView: NSView {
    var onContextClick: (UnitPoint) -> Void = { _ in }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }

        let isSecondaryClick = event.type == .rightMouseDown
        let isControlClick = event.type == .leftMouseDown
            && event.modifierFlags.contains(.control)
        return isSecondaryClick || isControlClick ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        reportContextClick(event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }

        reportContextClick(event)
    }

    private func reportContextClick(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let normalizedX = bounds.width > 0 ? location.x / bounds.width : 0.5
        let normalizedY = bounds.height > 0 ? location.y / bounds.height : 0.5

        onContextClick(
            UnitPoint(
                x: min(max(normalizedX, 0), 1),
                y: min(max(normalizedY, 0), 1)
            )
        )
    }
}
