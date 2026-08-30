//
//  ExplorerTheme.swift
//  FinallyExplorer
//

import AppKit
import SwiftUI

// DESIGN SPEC — adapted from the supplied palette and CleanMyMac references.
// VISUAL HIERARCHY
// 1. Primary: the window chrome and the active folder title.
// 2. Secondary: file names, selected navigation, and frequent actions.
// 3. Tertiary: paths, dates, sizes, dividers, and inactive panes.
// 4. Action: Mesa Sunrise coral for selection, focus, and primary controls.
//
// DESIGN SYSTEM
// - Surfaces: a continuous Imperial Primer shell around calm file surfaces.
// - Accents: Mesa Sunrise coral, Easy on the Eyes yellow, Glenwood Green.
// - Typography: SF Rounded for navigation/headings; SF Pro for dense file data.
// - Shape rhythm: 11pt controls, 16pt panels, continuous corners.
// - Motion: only 120ms press feedback on compact toolbar controls.
enum ExplorerTheme {
    // Supplied palette anchors.
    static let classicChalk = Color(hex: 0xF4F4F0)
    static let chinaSilk = Color(hex: 0xE3D1CC)
    static let mesaSunrise = Color(hex: 0xEA8160)
    static let imperialPrimer = Color(hex: 0x21303E)
    static let glenwoodGreen = Color(hex: 0xA7D3B7)
    static let shadedIvy = Color(hex: 0x254332)

    static let accent = mesaSunrise
    static let canvas = Color.adaptive(light: 0xF4F4F0, dark: 0x17242F)
    static let panel = Color.adaptive(light: 0xFCFBF7, dark: 0x21303E)
    static let elevatedPanel = Color.adaptive(light: 0xFFFFFF, dark: 0x293A47)
    static let control = Color.adaptive(light: 0xEEEAE4, dark: 0x30414C)
    static let row = Color.adaptive(light: 0xFCFBF7, dark: 0x21303E)
    static let selectedRow = Color.adaptive(light: 0xF5C8BA, dark: 0x704741)
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
    static let pdfIcon = Color.adaptive(light: 0xC64F52, dark: 0xFF8F91)
    static let videoIcon = Color.adaptive(light: 0x7659A6, dark: 0xC4A7F2)
    static let audioIcon = Color.adaptive(light: 0xA9587E, dark: 0xEFA2C5)
    static let codeIcon = Color.adaptive(light: 0x3975A5, dark: 0x7CC4F5)
    static let archiveIcon = Color.adaptive(light: 0xA97825, dark: 0xF2C76B)
    static let spreadsheetIcon = Color.adaptive(light: 0x3E7B57, dark: 0x89D5A5)
    static let presentationIcon = Color.adaptive(light: 0xB7653D, dark: 0xF2A17B)
    static let documentIcon = Color.adaptive(light: 0x68757E, dark: 0xC1C6BF)

    // The reference app treats the titlebar and navigation as one uninterrupted
    // product surface. These colors remain saturated in both appearances so the
    // shell never falls back to a disconnected system-white strip.
    static let chromeText = classicChalk
    static let chromeSecondaryText = chinaSilk.opacity(0.82)
    static let chromeDivider = Color.white.opacity(0.12)
    static let sidebarIconSurface = Color.white.opacity(0.09)

    static let windowChrome = LinearGradient(
        colors: [
            imperialPrimer,
            Color(hex: 0x342D43),
            Color(hex: 0x684047),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let sidebarBackground = LinearGradient(
        colors: [
            imperialPrimer,
            Color(hex: 0x293442),
            Color(hex: 0x352D42),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sidebarFooter = LinearGradient(
        colors: [Color(hex: 0x293442), Color(hex: 0x352D42)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let paneTitleFont = Font.system(.title3, design: .rounded).bold()
    static let navigationFont = Font.system(.body, design: .rounded).bold()
    static let actionFont = Font.system(.callout, design: .rounded).bold()
    static let fileNameFont = Font.system(.body, design: .rounded).weight(.medium)

    static let folderRowIconSize: CGFloat = 27
    static let fileRowIconSize: CGFloat = 21
    static let rowIconFrameSize: CGFloat = 34
}

struct ExplorerSidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 11) {
            configuration.icon
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ExplorerTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    ExplorerTheme.sidebarIconSurface,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            configuration.title
                .foregroundStyle(ExplorerTheme.chromeText)
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
            .frame(width: 34, height: 34)
            .background(
                configuration.isPressed
                    ? ExplorerTheme.accentSoft
                    : ExplorerTheme.elevatedPanel,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(ExplorerTheme.divider.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(
                color: ExplorerTheme.imperialPrimer.opacity(0.08),
                radius: 3,
                x: 0,
                y: 1
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ExplorerChromeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ExplorerTheme.chromeText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                configuration.isPressed
                    ? ExplorerTheme.accent.opacity(0.34)
                    : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ExplorerActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ExplorerTheme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(
                configuration.isPressed
                    ? ExplorerTheme.accentSoft
                    : ExplorerTheme.elevatedPanel,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(ExplorerTheme.divider.opacity(0.82), lineWidth: 0.75)
            }
            .shadow(
                color: ExplorerTheme.imperialPrimer.opacity(0.08),
                radius: configuration.isPressed ? 2 : 5,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ExplorerSidebarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ExplorerTheme.chromeText)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                configuration.isPressed
                    ? ExplorerTheme.accent.opacity(0.34)
                    : Color.white.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
