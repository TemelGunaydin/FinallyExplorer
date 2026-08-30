//
//  NearbyTransferSheet.swift
//  FinallyExplorer
//

import SwiftUI

struct NearbyTransferSheet: View {
    let presentation: NearbyTransferPresentation
    let coordinator: NearbyTransferCoordinator
    let defaultDestinationURL: URL

    var body: some View {
        switch presentation {
        case .devicePicker:
            NearbyDevicePickerView(coordinator: coordinator)
        case let .pairing(prompt):
            NearbyPairingView(prompt: prompt, coordinator: coordinator)
        case let .incomingOffer(offer):
            NearbyIncomingOfferView(
                offer: offer,
                defaultDestinationURL: defaultDestinationURL,
                coordinator: coordinator
            )
        }
    }
}
