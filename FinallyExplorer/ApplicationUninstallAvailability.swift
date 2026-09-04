//
//  ApplicationUninstallAvailability.swift
//  FinallyExplorer
//

import Foundation

nonisolated enum ApplicationUninstallAvailability: Equatable, Sendable {
    case notApplicable
    case available
    case unavailable
}
