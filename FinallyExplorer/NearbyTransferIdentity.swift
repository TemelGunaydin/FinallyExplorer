//
//  NearbyTransferIdentity.swift
//  FinallyExplorer
//

import Foundation

nonisolated struct NearbyTransferIdentity: Hashable, Sendable {
    private static let defaultsKey = "FinallyExplorer.NearbyTransfer.DeviceID"

    let deviceID: UUID
    let name: String

    static func current(defaults: UserDefaults = .standard) -> Self {
        let deviceID: UUID
        if let rawValue = defaults.string(forKey: defaultsKey),
           let storedID = UUID(uuidString: rawValue) {
            deviceID = storedID
        } else {
            deviceID = UUID()
            defaults.set(deviceID.uuidString, forKey: defaultsKey)
        }

        let rawName = Host.current().localizedName ?? "Mac"
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            deviceID: deviceID,
            name: String((trimmedName.isEmpty ? "Mac" : trimmedName).prefix(80))
        )
    }
}
