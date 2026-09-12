import SwiftUI

/// Shared, readable actions for sheets and popovers; toolbar styles stay intact.
struct ExplorerDialogButtonStyle: ButtonStyle {
    var isProminent = false
    var showsFocus = false

    func makeBody(configuration: Configuration) -> some View {
        ExplorerActionButtonSurface(isPressed: configuration.isPressed, isProminent: isProminent, showsFocus: showsFocus) {
            configuration.label
        }
    }
}
