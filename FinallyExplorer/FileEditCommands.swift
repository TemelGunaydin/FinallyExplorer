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
                if routeTextEditingCommand(#selector(NSText.cut(_:))) == false {
                    fileCommandContext?.cutSelection()
                }
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if routeTextEditingCommand(#selector(NSText.copy(_:))) == false {
                    fileCommandContext?.copySelection()
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if routeTextEditingCommand(#selector(NSText.paste(_:))) == false {
                    fileCommandContext?.paste()
                }
            }
            .keyboardShortcut("v", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Rename") {
                fileCommandContext?.renameSelection()
            }
            .disabled(fileCommandContext?.canRename != true)
        }
    }

    /// An active field editor keeps normal text editing behavior. Table and
    /// outline views may also claim these selectors even though they do not
    /// operate on FinallyExplorer's clipboard, so every non-text responder
    /// must fall back to the focused file command context.
    @discardableResult
    private func routeTextEditingCommand(_ action: Selector) -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }

        return NSApp.sendAction(action, to: textView, from: nil)
    }
}

extension FocusedValues {
    @Entry var explorerPaneID: UUID?
}
