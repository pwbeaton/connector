import Foundation

/// How the app was launched. Pass these as launch arguments, e.g.
/// `-demo YES -screen today -screenshots YES` (Xcode scheme or `simctl launch`).
///
/// - Demo mode uses built-in sample data instead of Google and Supabase, so the
///   app can be explored with no setup.
/// - `screen` opens a specific tab or onboarding step (used by CI screenshots).
/// - Screenshot mode turns off animations so captures show the final state.
nonisolated struct LaunchOptions: Equatable, Sendable {
    var isDemo = false
    var screen: String?
    var isScreenshotMode = false

    static func from(_ defaults: UserDefaults) -> LaunchOptions {
        LaunchOptions(
            isDemo: defaults.bool(forKey: "demo"),
            screen: defaults.string(forKey: "screen"),
            isScreenshotMode: defaults.bool(forKey: "screenshots")
        )
    }
}
