//
//  ExplorerTrafficLightKind.swift
//  FinallyExplorer
//

import SwiftUI

enum ExplorerTrafficLightKind {
    case close
    case minimize
    case fullscreen

    var color: Color {
        switch self {
        case .close:
            Color(red: 1, green: 0.37, blue: 0.34)
        case .minimize:
            Color(red: 1, green: 0.74, blue: 0.18)
        case .fullscreen:
            Color(red: 0.16, green: 0.78, blue: 0.25)
        }
    }

    var systemImage: String {
        switch self {
        case .close:
            "xmark"
        case .minimize:
            "minus"
        case .fullscreen:
            "arrow.up.left.and.arrow.down.right"
        }
    }

    var title: String {
        switch self {
        case .close:
            "Close Window"
        case .minimize:
            "Minimize Window"
        case .fullscreen:
            "Toggle Full Screen"
        }
    }
}
