//
//  FileOpenApplicationPresentationModifier.swift
//  FinallyExplorer
//

import SwiftUI

struct FileOpenApplicationPresentationModifier: ViewModifier {
    @Bindable var coordinator: FileOpenApplicationCoordinator

    func body(content: Content) -> some View {
        content
            .environment(coordinator)
            .alert(
                "Unable to Open File",
                isPresented: $coordinator.isErrorPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.errorMessage)
            }
    }
}

extension View {
    func fileOpenApplicationPresentation(
        coordinator: FileOpenApplicationCoordinator
    ) -> some View {
        modifier(
            FileOpenApplicationPresentationModifier(coordinator: coordinator)
        )
    }
}
