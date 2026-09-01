//
//  SidebarVisibilityStoring.swift
//  FinallyExplorer
//

@MainActor
protocol SidebarVisibilityStoring {
    func loadHiddenBuiltInPlaces() -> Set<SidebarBuiltInPlace>
    func saveHiddenBuiltInPlaces(_ places: Set<SidebarBuiltInPlace>)
}
