import SwiftUI
import UIKit

/// The "training camp" look: dark-first, sleek, big rounded numerals.
///
/// Color rules:
/// - Recovery band colors (green / yellow / red) appear only on Recovery.
/// - Sleep is violet, Effort and activity are electric blue.
/// - Everything else is neutral, so the three score colors stand out.
enum Theme {
    // MARK: Surfaces and text
    static let background = Color(light: 0xF3F4F7, dark: 0x07090C)
    static let surface = Color(light: 0xFFFFFF, dark: 0x12161C)
    static let surfaceRaised = Color(light: 0xEBEDF1, dark: 0x1B2129)
    static let textPrimary = Color(light: 0x0B0D10, dark: 0xF2F4F7)
    static let textSecondary = Color(light: 0x5B6474, dark: 0x8A94A6)
    static let hairline = Color(light: 0x0B0D10, dark: 0xFFFFFF).opacity(0.08)

    // MARK: Score colors
    static let recoveryGo = Color(light: 0x0FB868, dark: 0x16E07F)
    static let recoverySteady = Color(light: 0xD99A00, dark: 0xFFC83D)
    static let recoveryRest = Color(light: 0xE5303F, dark: 0xFF4D5E)
    static let sleep = Color(light: 0x6A55F0, dark: 0x8F7BFF)
    static let effort = Color(light: 0x1484E0, dark: 0x2EA8FF)

    // MARK: Tier metals
    static let bronze = Color(light: 0xA86B3C, dark: 0xD39A6A)
    static let silver = Color(light: 0x7D8896, dark: 0xC9D1DB)
    static let gold = Color(light: 0xC99A1E, dark: 0xF2C14E)
    static let platinum = Color(light: 0x2BA59B, dark: 0x9FE8E1)

    // MARK: Layout
    static let cornerRadius: CGFloat = 20
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    /// Comfortably above Apple's 44-point minimum tap target.
    static let buttonHeight: CGFloat = 54
}

extension Font {
    /// Big score numerals: rounded, with fixed-width digits so they don't jiggle.
    static func scoreNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Small uppercase section label, e.g. "RECOVERY".
    func sectionLabel() -> some View {
        font(.caption.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    /// A rounded card on the raised surface color.
    func card() -> some View {
        padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension Color {
    /// A color that switches between two hex values in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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

/// The full-width button at the bottom of onboarding screens.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(.white)
            .background(Theme.effort, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// A quieter full-width button (outlined).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
