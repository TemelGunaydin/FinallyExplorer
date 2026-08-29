//
//  FileEditCommands.swift
//  FinallyExplorer
//

import AppKit
import Foundation
import SwiftUI

struct FileEditCommands: Commands {
    @FocusedValue(\.fileCommandContext) private var fileCommandContext

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if routeResponderCommand(#selector(NSText.cut(_:))) == false {
                    fileCommandContext?.cutSelection()
                }
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if routeResponderCommand(#selector(NSText.copy(_:))) == false {
                    fileCommandContext?.copySelection()
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if routeResponderCommand(#selector(NSText.paste(_:))) == false {
                    fileCommandContext?.paste()
                }
            }
            .keyboardShortcut("v", modifiers: .command)
        }
    }

    /// Search fields, selectable text, and other AppKit responders retain
    /// their normal editing behavior. File commands are the fallback when the
    /// current responder chain does not handle the standard selector.
    @discardableResult
    private func routeResponderCommand(_ action: Selector) -> Bool {
        return NSApp.sendAction(action, to: nil, from: nil)
    }
}

extension FocusedValues {
    @Entry var explorerPaneID: UUID?
}
