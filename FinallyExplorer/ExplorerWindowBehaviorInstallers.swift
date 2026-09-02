//
//  ExplorerWindowBehaviorInstallers.swift
//  FinallyExplorer
//

import SwiftUI

struct ExplorerWindowBehaviorInstallers: View {
    let navigateBack: () -> Bool

    var body: some View {
        ZStack {
            ExplorerWindowTrafficControlsInstaller()
            MouseBackNavigationMonitor(navigateBack: navigateBack)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
