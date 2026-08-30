//
//  NearbyPairingView.swift
//  FinallyExplorer
//

import SwiftUI

struct NearbyPairingView: View {
    @Environment(\.explorerTheme) private var theme

    let prompt: NearbyPairingPrompt
    let coordinator: NearbyTransferCoordinator

    private var isConfirmed: Bool {
        coordinator.confirmedPairingSessionIDs.contains(prompt.id)
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(theme.accent)

            Text("Verify \(prompt.peerName)")
                .font(ExplorerTheme.paneTitleFont)

            Text("Make sure this exact code is visible on both Macs.")
                .foregroundStyle(theme.textSecondary)

            Text(groupedCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .tracking(4)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("nearby-pairing-code")

            if isConfirmed {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for \(prompt.peerName)…")
                }
                .foregroundStyle(theme.textSecondary)
            } else {
                HStack(spacing: 12) {
                    Button("Codes Do Not Match", role: .destructive) {
                        coordinator.declinePairing(prompt)
                    }
                    .accessibilityIdentifier("nearby-pairing-decline-button")

                    Button("Codes Match") {
                        coordinator.confirmPairing(prompt)
                    }
                    .buttonStyle(ExplorerActionButtonStyle())
                    .accessibilityIdentifier("nearby-pairing-confirm-button")
                }
            }
        }
        .padding(28)
        .frame(width: 460, height: 350)
        .background(theme.elevatedPanel)
        .foregroundStyle(theme.textPrimary)
        .accessibilityIdentifier("nearby-pairing-sheet")
    }

    private var groupedCode: String {
        guard prompt.code.count == 8 else { return prompt.code }
        let middle = prompt.code.index(prompt.code.startIndex, offsetBy: 4)
        return "\(prompt.code[..<middle])  \(prompt.code[middle...])"
    }
}
