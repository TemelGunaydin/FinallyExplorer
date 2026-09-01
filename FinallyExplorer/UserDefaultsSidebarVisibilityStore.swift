//
//  UserDefaultsSidebarVisibilityStore.swift
//  FinallyExplorer
//

import Foundation

@MainActor
struct UserDefaultsSidebarVisibilityStore: SidebarVisibilityStoring {
    private static let storageKey = "sidebar-hidden-built-ins-v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadHiddenBuiltInPlaces() -> Set<SidebarBuiltInPlace> {
        let rawValues = defaults.stringArray(forKey: Self.storageKey) ?? []
        return Set(rawValues.compactMap(SidebarBuiltInPlace.init(rawValue:)))
    }

    func saveHiddenBuiltInPlaces(_ places: Set<SidebarBuiltInPlace>) {
        defaults.set(
            places.map(\.rawValue).sorted(),
            forKey: Self.storageKey
        )
    }
}
