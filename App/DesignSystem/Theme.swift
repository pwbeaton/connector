import SwiftUI

/// Shared sizes so screens look consistent. Colors come from the asset catalog:
/// the single accent color is AccentColor (used via `.tint`). Green, yellow,
/// and red are reserved for vendor score bands, so don't use them elsewhere.
enum Theme {
    static let cornerRadius: CGFloat = 16
    static let screenPadding: CGFloat = 24
    /// Comfortably above Apple's 44-point minimum tap target.
    static let buttonHeight: CGFloat = 52
}

/// The full-width button at the bottom of onboarding screens.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(.white)
            .background(.tint, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
