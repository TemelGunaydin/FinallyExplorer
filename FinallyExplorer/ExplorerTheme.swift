//
//  ExplorerTheme.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

// DESIGN SPEC — adapted from the supplied palette and CleanMyMac references.
// VISUAL HIERARCHY
// 1. Primary: the active file pane and its current folder title.
// 2. Secondary: file names and the selected sidebar location.
// 3. Tertiary: paths, dates, sizes, dividers, and inactive panes.
// 4. Action: Mesa Sunrise coral for selection, focus, and primary controls.
//
// DESIGN SYSTEM
// - Surfaces: Classic Chalk by day, Imperial Primer-derived navy by night.
// - Accents: Mesa Sunrise coral, Easy on the Eyes yellow, Glenwood Green.
// - Typography: SF Rounded for navigation/headings; SF Pro for dense file data.
// - Shape rhythm: 10pt controls, 14pt panels, continuous corners.
// - Motion: only 120ms press feedback on compact toolbar controls.
enum ExplorerTheme {
    // Supplied palette anchors.
    static let classicChalk = Color(hex: 0xF4F4F0)
    static let chinaSilk = Color(hex: 0xE3D1CC)
    static let easyOnTheEyes = Color(hex: 0xF9ECB6)
    static let mesaSunrise = Color(hex: 0xEA8160)
    static let carpeDiem = Color(hex: 0x905755)
    static let imperialPrimer = Color(hex: 0x21303E)
    static let glenwoodGreen = Color(hex: 0xA7D3B7)
    static let shadedIvy = Color(hex: 0x254332)

    static let accent = mesaSunrise
    static let canvas = Color.adaptive(light: 0xF4F4F0, dark: 0x17242F)
    static let panel = Color.adaptive(light: 0xFCFBF7, dark: 0x21303E)
    static let elevatedPanel = Color.adaptive(light: 0xFFFFFF, dark: 0x293A47)
    static let control = Color.adaptive(light: 0xEEEAE4, dark: 0x30414C)
    static let row = Color.adaptive(light: 0xFCFBF7, dark: 0x21303E)
    static let inspector = Color.adaptive(light: 0xF7F3EE, dark: 0x1D2B36)

    static let textPrimary = Color.adaptive(light: 0x21303E, dark: 0xF4F4F0)
    static let textSecondary = Color.adaptive(light: 0x65717A, dark: 0xC1C6BF)
    static let textTertiary = Color.adaptive(light: 0x8B8581, dark: 0x909B99)
    static let divider = Color.adaptive(light: 0xDDD4CD, dark: 0x3B4A56)

    static let accentSoft = Color.adaptive(light: 0xF8D8CD, dark: 0x593B3A)
    static let warmHighlight = Color.adaptive(light: 0xD7A838, dark: 0xF9ECB6)
    static let supportAccent = Color.adaptive(light: 0x3F8064, dark: 0xA7D3B7)
    static let folderIcon = Color.adaptive(light: 0xD65F42, dark: 0xFF9B7B)
    static let imageIcon = Color.adaptive(light: 0x3F8064, dark: 0xA7D3B7)
    static let documentIcon = Color.adaptive(light: 0x68757E, dark: 0xC1C6BF)

    static let sidebarBackground = LinearGradient(
        colors: [
            Color.adaptive(light: 0xF4F4F0, dark: 0x21303E),
            Color.adaptive(light: 0xE3D1CC, dark: 0x3A2938),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let assistantHeader = LinearGradient(
        colors: [imperialPrimer, carpeDiem, mesaSunrise],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let paneTitleFont = Font.system(.headline, design: .rounded).bold()
    static let navigationFont = Font.system(.body, design: .rounded).weight(.medium)
    static let assistantTitleFont = Font.system(.title2, design: .rounded).bold()
}

struct ExplorerSidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ExplorerTheme.accent)
                .frame(width: 20)

            configuration.title
                .foregroundStyle(ExplorerTheme.textPrimary)
        }
    }
}

struct ExplorerToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                isEnabled ? ExplorerTheme.textPrimary : ExplorerTheme.textTertiary
            )
            .frame(width: 30, height: 28)
            .background(
                configuration.isPressed
                    ? ExplorerTheme.accentSoft
                    : ExplorerTheme.control,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(ExplorerTheme.divider.opacity(0.72), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    fileprivate static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
