import CoreText
import SwiftUI
import UIKit

/// Pluto's look: calm navy ink on cool grey, one teal accent, violet for sleep and
/// burnt orange for effort. Numbers are set in a condensed Archivo; small labels in
/// IBM Plex Mono. Every value here comes from the "Fitbit Air Tracker Redesign" spec
/// (light and dark boards).
enum Theme {
    // MARK: Surfaces
    static let background = Color(light: 0xF2F4F5, dark: 0x0B141B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x131F28)
    /// Chips, pills, and the "about the same" capsule.
    static let surfaceRaised = Color(light: 0xF2F4F5, dark: 0x1A2730)
    /// The 1 px ring around cards.
    static let cardStroke = Color(light: 0xE3E8EB, dark: 0x1E2C36)
    /// Dividers inside cards.
    static let hairline = Color(light: 0xE8ECEF, dark: 0x22313B)
    /// Grid lines inside charts.
    static let gridLine = Color(light: 0xEEF1F3, dark: 0x1E2C36)
    /// Chart baselines.
    static let baseline = Color(light: 0xD3DADF, dark: 0x2E3D47)
    /// Outline of round buttons and segmented controls.
    static let controlStroke = Color(light: 0xDDE3E7, dark: 0x2A3943)

    // MARK: Text
    static let textPrimary = Color(light: 0x0C1B26, dark: 0xEEF2F4)
    /// Body copy and secondary values.
    static let textSecondary = Color(light: 0x44535E, dark: 0xB3C0C8)
    /// Labels, captions, axis text.
    static let textMuted = Color(light: 0x5F6D78, dark: 0x8696A1)
    /// Disabled icons and empty streaks.
    static let textFaint = Color(light: 0x9AA7B0, dark: 0x4C5D68)

    // MARK: Inverse (filled navy controls; they turn light in dark mode)
    static let inverse = Color(light: 0x0C1B26, dark: 0xEEF2F4)
    static let onInverse = Color(light: 0xFFFFFF, dark: 0x0B141B)

    // MARK: Ticks and markers
    static let tickMinor = Color(light: 0xD3DADF, dark: 0x2A3943)
    static let tickMajor = Color(light: 0xB4BFC6, dark: 0x3E4F5B)
    static let markerDashed = Color(light: 0x7D8B95, dark: 0x6E7F8A)
    static let trackLine = Color(light: 0xE1E6EA, dark: 0x1E2C36)

    // MARK: Score colors
    static let teal = Color(light: 0x0B7A75, dark: 0x3CC2B4)
    static let tealDeep = Color(light: 0x08605B, dark: 0x6FD9CC)
    static let tealTint = Color(light: 0xE1F0EE, dark: 0x0F3533)
    static let tealRow = Color(light: 0xEEF6F5, dark: 0x0F2B2A)
    static let tealTrack = Color(light: 0xD8E8E6, dark: 0x1C3A38)
    static let recoveryBar = Color(light: 0x1F8E86, dark: 0x34B3A6)

    static let sleep = Color(light: 0x5B4BD6, dark: 0x9D91FF)
    static let sleepTint = Color(light: 0xECE9FB, dark: 0x262249)
    static let sleepStem = Color(light: 0xE7E4FB, dark: 0x2A2550)

    static let effort = Color(light: 0xC2410C, dark: 0xFF8F52)
    static let effortText = Color(light: 0xA63A0B, dark: 0xFFB089)
    static let effortTint = Color(light: 0xFBE6D8, dark: 0x3A2418)
    static let effortBar = Color(light: 0xD9622B, dark: 0xE8763C)

    static let goldText = Color(light: 0x8A6A00, dark: 0xE8C25A)
    static let goldTint = Color(light: 0xF6EFD9, dark: 0x3A3018)

    /// Recovery bands: Go and Steady share the teal accent; Recover warns in orange.
    static let recoveryGo = teal
    static let recoverySteady = teal
    static let recoveryRest = effort

    // MARK: Tier metals
    static let bronze = Color(light: 0xB07A4F, dark: 0xD39A6A)
    static let silver = Color(light: 0xA3AEB6, dark: 0xA3AEB6)
    static let gold = Color(light: 0xB8860B, dark: 0xE2B53E)
    static let platinum = Color(light: 0x5FA8A1, dark: 0x9FE8E1)

    // MARK: Navigation bar
    static let navBackground = Color(light: 0x0C1B26, dark: 0x18252E)
    static let navActive = Color(light: 0x273841, dark: 0xEEF2F4)
    static let navActiveText = Color(light: 0xFFFFFF, dark: 0x0B141B)
    static let navInactive = Color(light: 0x93A3AE, dark: 0x8696A1)

    // MARK: Layout
    static let cornerRadius: CGFloat = 26
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 22
    /// Comfortably above Apple's 44-point minimum tap target.
    static let buttonHeight: CGFloat = 56
}

/// Archivo (variable: weight 100–900, width 62–125%) and IBM Plex Mono, both under the SIL
/// Open Font License and bundled in Shared/Fonts. The redesign leans on Archivo's width axis:
/// condensed numerals (66–75%), slightly narrowed headings (85%), normal-width text.
enum Typeface {
    static let archivo = "Archivo-SemiBold"
    static let monoRegular = "IBMPlexMono-Regular"
    static let monoMedium = "IBMPlexMono-Medium"

    /// Line heights at `line-height: normal`, as a multiple of the font size (hhea ascent + descent).
    /// SwiftUI sizes a line to exactly this; `lineBox` trims or pads it to the spec's CSS line height.
    static let archivoNaturalLineHeight: CGFloat = 1.088
    static let monoNaturalLineHeight: CGFloat = 1.3

    private static let weightAxis = 0x7767_6874 // 'wght'
    private static let widthAxis = 0x7764_7468  // 'wdth'

    /// The variable font straight from the bundled file, so it never depends on name lookup.
    private static let archivoBase: CTFontDescriptor = {
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(forResource: "Archivo-Variable", withExtension: "ttf"),
               let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first {
                return first
            }
        }
        return CTFontDescriptorCreateWithNameAndSize(archivo as CFString, 0)
    }()

    /// Archivo at a weight (100–900) and width (62–125%). Digits are tabular like the spec
    /// (`font-variant-numeric: tabular-nums`), baked into the font rather than applied with
    /// SwiftUI's `.monospacedDigit()`, which can rebuild the font and drop the width axis.
    static func archivo(size: CGFloat, weight: Double, width: Double, tabular: Bool = true) -> CTFont {
        var attributes: [CFString: Any] = [kCTFontVariationAttribute: [weightAxis: weight, widthAxis: width]]
        if tabular {
            attributes[kCTFontFeatureSettingsAttribute] = [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]]
        }
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(archivoBase, attributes as CFDictionary), size, nil)
    }

    static func numericWeight(_ weight: Font.Weight) -> Double {
        switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    /// iOS's default point sizes for each text style.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 40
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .headline: .bold
        case .largeTitle: .bold
        default: .regular
        }
    }

    /// Headings are set a little narrower than body text.
    static func width(_ style: Font.TextStyle) -> Double {
        switch style {
        case .largeTitle, .title, .title2: 85
        default: 100
        }
    }
}

extension Font {
    /// Archivo at an exact size, weight, and width (percent of normal).
    static func archivo(_ size: CGFloat, _ weight: Font.Weight = .regular, width: Double = 100, tabular: Bool = true) -> Font {
        Font(Typeface.archivo(size: size, weight: Typeface.numericWeight(weight), width: width, tabular: tabular))
    }

    /// IBM Plex Mono, for small uppercase labels, dates, and axis ticks.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular ? Typeface.monoRegular : Typeface.monoMedium, fixedSize: size)
    }

    /// App text in a given style.
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        archivo(Typeface.size(style), weight ?? Typeface.defaultWeight(style), width: Typeface.width(style))
    }

    /// App text at a fixed size.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        archivo(size, weight)
    }

    /// Big score numerals: semibold Archivo at 66% width with tabular digits.
    static func scoreNumber(_ size: CGFloat, tabular: Bool = true, width: Double = 66) -> Font {
        archivo(size, .semibold, width: width, tabular: tabular)
    }
}

extension View {
    /// Sizes text to a CSS `line-height` (a multiple of `size`), the way the spec lays it out.
    /// A big number at `line-height: 0.8` sits in a box 0.8× its size, not the font's natural
    /// 1.088×, so the space above and below it matches the design. Extra height on multi-line
    /// text goes between lines too.
    func lineBox(_ multiple: CGFloat, size: CGFloat, natural: CGFloat = Typeface.archivoNaturalLineHeight) -> some View {
        let extra = (multiple - natural) * size
        return lineSpacing(max(0, extra)).padding(.vertical, extra / 2)
    }

    /// Small uppercase mono label, e.g. "RECOVERY".
    func sectionLabel(_ color: Color = Theme.textMuted) -> some View {
        font(.mono(11, .medium))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// A white card with a hairline ring and generous corners.
    func card(padding: EdgeInsets = EdgeInsets(top: 20, leading: 25, bottom: 22, trailing: 25),
              radius: CGFloat = Theme.cornerRadius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    /// A large screen title: "Today", "Team".
    func screenTitle(_ size: CGFloat = 40) -> some View {
        font(.archivo(size, .bold, width: 85)).tracking(-size * 0.02).foregroundStyle(Theme.textPrimary)
            .lineBox(1, size: size)
    }

    /// A section heading inside a screen: "Streaks", "Leaderboard".
    func sectionHeading() -> some View {
        font(.archivo(24, .bold, width: 85)).tracking(-0.24).foregroundStyle(Theme.textPrimary)
            .lineBox(1, size: 24)
    }

    /// The mono eyebrow above a screen title: "TUE · OCT 27".
    func eyebrow() -> some View {
        font(.mono(12, .medium)).tracking(0.96).textCase(.uppercase).foregroundStyle(Theme.textMuted)
    }
}

extension Color {
    /// A color that switches between two hex values in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The filled navy button (white in dark mode), e.g. "Sign in", "Save goals".
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.archivo(17, .bold))
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(Theme.onInverse)
            .background(Theme.inverse, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// The outlined button, e.g. "See all 20 badges".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.archivo(15, .bold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Theme.textPrimary)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.controlStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
