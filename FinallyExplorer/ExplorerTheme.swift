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
struct ExplorerTheme {
    let choice: ExplorerThemeChoice
    let classicChalk: Color
    let chinaSilk: Color
    let imperialPrimer: Color
    let accent: Color
    let canvas: Color
    let panel: Color
    let elevatedPanel: Color
    let control: Color
    let row: Color
    let selectedRow: Color
    let inspector: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let divider: Color
    let accentSoft: Color
    let warmHighlight: Color
    let supportAccent: Color
    let folderIcon: Color
    let imageIcon: Color
    let pdfIcon: Color
    let videoIcon: Color
    let audioIcon: Color
    let codeIcon: Color
    let archiveIcon: Color
    let spreadsheetIcon: Color
    let presentationIcon: Color
    let documentIcon: Color
    let chromeText: Color
    let chromeSecondaryText: Color
    let chromeDivider: Color
    let windowChrome: LinearGradient
    let sidebarBackground: LinearGradient
    let sidebarFooter: LinearGradient

    static let paneTitleFont = Font.system(.title3, design: .rounded).bold()
    static let navigationFont = Font.system(.body, design: .rounded).bold()
    static let sidebarNavigationFont = Font.system(
        size: 16,
        weight: .bold,
        design: .rounded
    )
    static let actionFont = Font.system(.callout, design: .rounded).bold()
    static let fileNameFont = Font.system(.body, design: .rounded).weight(.medium)

    static let folderRowIconSize: CGFloat = 27
    static let fileRowIconSize: CGFloat = 21
    static let rowIconFrameSize: CGFloat = 34

    static func palette(for choice: ExplorerThemeChoice) -> Self {
        switch choice {
        case .mesa:
            make(
                choice: choice,
                accent: 0xEA8160,
                support: 0x3F8064,
                warm: 0xD7A838,
                canvas: (0xF4F4F0, 0x17242F),
                panel: (0xFCFBF7, 0x21303E),
                elevated: (0xFFFFFF, 0x293A47),
                control: (0xEEEAE4, 0x30414C),
                selected: (0xF8E4DC, 0x4B3639),
                primaryText: (0x21303E, 0xF4F4F0),
                secondaryText: (0x65717A, 0xC1C6BF),
                tertiaryText: (0x8B8581, 0x909B99),
                divider: (0xDDD4CD, 0x3B4A56),
                accentSoft: (0xF8D8CD, 0x593B3A),
                shell: (0x21303E, 0x342D43, 0x684047)
            )
        case .midnight:
            make(
                choice: choice,
                accent: 0x9A8CFF,
                support: 0x4DD7D1,
                warm: 0xF2BE5C,
                canvas: (0xF2F3FA, 0x111421),
                panel: (0xFBFBFF, 0x191D2C),
                elevated: (0xFFFFFF, 0x23283A),
                control: (0xE9EAF4, 0x2B3145),
                selected: (0xE9E5FF, 0x393458),
                primaryText: (0x20243A, 0xF5F4FF),
                secondaryText: (0x626880, 0xC3C6D8),
                tertiaryText: (0x898DA0, 0x8D93A8),
                divider: (0xD8DAE7, 0x383E53),
                accentSoft: (0xE3DEFF, 0x3E385F),
                shell: (0x171B2C, 0x25243B, 0x47304B)
            )
        case .ocean:
            make(
                choice: choice,
                accent: 0x2E9CCA,
                support: 0x36B890,
                warm: 0xF2B84B,
                canvas: (0xEFF7F9, 0x10232B),
                panel: (0xFAFEFF, 0x18313A),
                elevated: (0xFFFFFF, 0x21404A),
                control: (0xE3F0F3, 0x294C56),
                selected: (0xD9F1F8, 0x244B5A),
                primaryText: (0x18343F, 0xF2FBFD),
                secondaryText: (0x58727B, 0xB8CDD2),
                tertiaryText: (0x80959B, 0x86A2A9),
                divider: (0xCFE0E4, 0x345761),
                accentSoft: (0xCFEDF6, 0x245566),
                shell: (0x12303B, 0x164657, 0x245A68)
            )
        case .forest:
            make(
                choice: choice,
                accent: 0x49A36D,
                support: 0x5A8FD8,
                warm: 0xD7A63E,
                canvas: (0xF1F6F0, 0x15241C),
                panel: (0xFBFEFA, 0x1D3025),
                elevated: (0xFFFFFF, 0x274034),
                control: (0xE5EEE4, 0x304C3D),
                selected: (0xDDF0E2, 0x2E523E),
                primaryText: (0x20362A, 0xF2FAF4),
                secondaryText: (0x617568, 0xBDD0C2),
                tertiaryText: (0x86958A, 0x8EA598),
                divider: (0xD2DED4, 0x395846),
                accentSoft: (0xD4EBD9, 0x31583F),
                shell: (0x193326, 0x264338, 0x3D4A3B)
            )
        case .graphite:
            make(
                choice: choice,
                accent: 0xE06C9F,
                support: 0x6A9FE6,
                warm: 0xD8A84F,
                canvas: (0xF4F3F5, 0x18191D),
                panel: (0xFCFBFD, 0x23242A),
                elevated: (0xFFFFFF, 0x2D2E35),
                control: (0xECE9EE, 0x383941),
                selected: (0xF5DFE9, 0x513543),
                primaryText: (0x29272D, 0xF7F4F7),
                secondaryText: (0x6E6972, 0xC8C3CA),
                tertiaryText: (0x918B94, 0x97929B),
                divider: (0xDED9E0, 0x484850),
                accentSoft: (0xF2D6E3, 0x5A3547),
                shell: (0x25262C, 0x39313F, 0x5A3547)
            )
        }
    }

    private static func make(
        choice: ExplorerThemeChoice,
        accent accentHex: UInt32,
        support supportHex: UInt32,
        warm warmHex: UInt32,
        canvas: (light: UInt32, dark: UInt32),
        panel: (light: UInt32, dark: UInt32),
        elevated: (light: UInt32, dark: UInt32),
        control: (light: UInt32, dark: UInt32),
        selected: (light: UInt32, dark: UInt32),
        primaryText: (light: UInt32, dark: UInt32),
        secondaryText: (light: UInt32, dark: UInt32),
        tertiaryText: (light: UInt32, dark: UInt32),
        divider: (light: UInt32, dark: UInt32),
        accentSoft: (light: UInt32, dark: UInt32),
        shell: (start: UInt32, middle: UInt32, end: UInt32)
    ) -> Self {
        let accent = Color(hex: accentHex)
        let support = Color(hex: supportHex)
        let warm = Color(hex: warmHex)
        let shellStart = Color(hex: shell.start)
        let shellMiddle = Color(hex: shell.middle)
        let shellEnd = Color(hex: shell.end)
        let classicChalk = Color(hex: 0xF4F4F0)
        let chinaSilk = Color(hex: 0xE3D1CC)
        let panelColor = Color.adaptive(light: panel.light, dark: panel.dark)

        return Self(
            choice: choice,
            classicChalk: classicChalk,
            chinaSilk: chinaSilk,
            imperialPrimer: shellStart,
            accent: accent,
            canvas: .adaptive(light: canvas.light, dark: canvas.dark),
            panel: panelColor,
            elevatedPanel: .adaptive(light: elevated.light, dark: elevated.dark),
            control: .adaptive(light: control.light, dark: control.dark),
            row: panelColor,
            selectedRow: .adaptive(light: selected.light, dark: selected.dark),
            inspector: panelColor,
            textPrimary: .adaptive(
                light: primaryText.light,
                dark: primaryText.dark
            ),
            textSecondary: .adaptive(
                light: secondaryText.light,
                dark: secondaryText.dark
            ),
            textTertiary: .adaptive(
                light: tertiaryText.light,
                dark: tertiaryText.dark
            ),
            divider: .adaptive(light: divider.light, dark: divider.dark),
            accentSoft: .adaptive(
                light: accentSoft.light,
                dark: accentSoft.dark
            ),
            warmHighlight: warm,
            supportAccent: support,
            folderIcon: accent,
            imageIcon: support,
            pdfIcon: accent,
            videoIcon: support,
            audioIcon: warm,
            codeIcon: support,
            archiveIcon: warm,
            spreadsheetIcon: support,
            presentationIcon: accent,
            documentIcon: .adaptive(
                light: secondaryText.light,
                dark: secondaryText.dark
            ),
            chromeText: classicChalk,
            chromeSecondaryText: chinaSilk.opacity(0.82),
            chromeDivider: Color.white.opacity(0.12),
            windowChrome: LinearGradient(
                colors: [shellStart, shellMiddle, shellEnd],
                startPoint: .leading,
                endPoint: .trailing
            ),
            sidebarBackground: LinearGradient(
                colors: [shellStart, shellMiddle, shellEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            sidebarFooter: LinearGradient(
                colors: [shellMiddle, shellEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

nonisolated enum ExplorerThemeChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case mesa
    case midnight
    case ocean
    case forest
    case graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .mesa: "Mesa"
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .graphite: "Graphite"
        }
    }
}

extension EnvironmentValues {
    @Entry var explorerTheme = ExplorerTheme.palette(for: .mesa)
}

struct ExplorerSidebarLabelStyle: LabelStyle {
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .frame(width: 27, height: 28)

            configuration.title
                .foregroundStyle(theme.chromeText)
        }
    }
}

struct ExplorerToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                isEnabled ? theme.textPrimary : theme.textTertiary
            )
            .frame(width: 34, height: 34)
            .background {
                ExplorerRaisedButtonSurface(
                    cornerRadius: 11,
                    pressedOverlay: configuration.isPressed
                        ? theme.accentSoft.opacity(0.72)
                        : .clear
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.divider.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(
                color: Color.black.opacity(0.16),
                radius: 1,
                x: 0,
                y: 1
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.13),
                radius: 4,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ExplorerChromeIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                isEnabled ? theme.chromeText : theme.chromeSecondaryText
            )
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.34))
                    .offset(y: 2)

                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.imperialPrimer)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                theme.accent.opacity(
                                    configuration.isPressed ? 0.18 : 0.08
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.chromeDivider, lineWidth: 0.75)
            }
            .shadow(
                color: Color.black.opacity(0.26),
                radius: 2,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.56)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct ExplorerActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background {
                ExplorerRaisedButtonSurface(
                    cornerRadius: 11,
                    pressedOverlay: configuration.isPressed
                        ? theme.accentSoft.opacity(0.72)
                        : .clear
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.divider.opacity(0.82), lineWidth: 0.75)
            }
            .shadow(
                color: Color.black.opacity(0.16),
                radius: 1,
                x: 0,
                y: 1
            )
            .shadow(
                color: theme.imperialPrimer.opacity(0.14),
                radius: 5,
                x: 0,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ExplorerRaisedButtonSurface: View {
    @Environment(\.explorerTheme) private var theme

    let cornerRadius: CGFloat
    let pressedOverlay: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(theme.elevatedPanel)
            .overlay {
                shape.fill(pressedOverlay)
            }
    }
}

struct ExplorerSidebarActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.explorerTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ExplorerTheme.actionFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.chromeText)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .offset(y: 3)

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.imperialPrimer)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                theme.accent.opacity(
                                    configuration.isPressed ? 0.3 : 0.16
                                )
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(0.28),
                radius: 2,
                x: 0,
                y: 3
            )
            .shadow(
                color: theme.accent.opacity(0.14),
                radius: 6,
                x: 0,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
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
