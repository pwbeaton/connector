import Foundation
import Testing
@testable import App

struct AppConfigTests {
    private let valid: [String: Any] = [
        "SupabaseURL": "https://abcd1234.supabase.co",
        "SupabaseAnonKey": "sb_publishable_123",
        "GoogleClientID": "1234-abc.apps.googleusercontent.com",
        "GoogleRedirectScheme": "com.googleusercontent.apps.1234-abc",
        "AppURLScheme": "plutoapp",
    ]

    private func with(_ changes: [String: Any]) -> [String: Any] {
        valid.merging(changes) { _, new in new }
    }

    @Test func loadsValidValues() throws {
        let config = try AppConfig.load(from: valid)
        #expect(config.supabaseURL == URL(string: "https://abcd1234.supabase.co"))
        #expect(config.supabaseKey == "sb_publishable_123")
        #expect(config.googleClientID == "1234-abc.apps.googleusercontent.com")
        #expect(config.googleRedirectScheme == "com.googleusercontent.apps.1234-abc")
        #expect(config.appURLScheme == "plutoapp")
    }

    @Test func acceptsLocalStack() throws {
        let config = try AppConfig.load(from: with(["SupabaseURL": "http://127.0.0.1:54321"]))
        #expect(config.supabaseURL.port == 54321)
    }

    @Test func missingSecretsFileIsReported() {
        // Without Secrets.xcconfig the build settings expand to empty strings.
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: with(["SupabaseURL": "", "SupabaseAnonKey": ""]))
        }
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: [:])
        }
    }

    @Test func exampleValuesAreReportedAsMissing() {
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: with([
                "SupabaseURL": "https://your-project-ref.supabase.co",
                "SupabaseAnonKey": "your-anon-or-publishable-key",
            ]))
        }
    }

    @Test func urlWithoutHostIsRejected() {
        // What you get if the "https:/$()/" trick is left out of the xcconfig.
        #expect(throws: AppConfig.LoadError.invalidURL("https:")) {
            try AppConfig.load(from: with(["SupabaseURL": "https:"]))
        }
    }

    @Test func placeholderGoogleClientIsReported() {
        #expect(throws: AppConfig.LoadError.missingGoogleClient) {
            try AppConfig.load(from: with(["GoogleClientID": "placeholder.apps.googleusercontent.com"]))
        }
        #expect(throws: AppConfig.LoadError.missingGoogleClient) {
            try AppConfig.load(from: with(["GoogleClientID": ""]))
        }
    }
}

struct LaunchOptionsTests {
    @Test func readsLaunchArguments() throws {
        let defaults = try #require(UserDefaults(suiteName: "LaunchOptionsTests"))
        defer { defaults.removePersistentDomain(forName: "LaunchOptionsTests") }
        defaults.set(true, forKey: "demo")
        defaults.set("team", forKey: "screen")
        defaults.set(true, forKey: "screenshots")

        let options = LaunchOptions.from(defaults)
        #expect(options == LaunchOptions(isDemo: true, screen: "team", isScreenshotMode: true))
    }

    @Test func defaultsToANormalLaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "LaunchOptionsTests-empty"))
        #expect(LaunchOptions.from(defaults) == LaunchOptions())
    }
}

struct AppModelTests {
    @Test func demoLaunchSkipsConfig() {
        let model = AppModel(options: LaunchOptions(isDemo: true)) {
            Issue.record("config should not be loaded in demo mode")
            throw AppConfig.LoadError.missingSecrets
        }
        #expect(model.mode == .demo)
    }

    @Test func missingConfigOffersDemo() {
        let model = AppModel(options: LaunchOptions()) { throw AppConfig.LoadError.missingGoogleClient }
        #expect(model.mode == .setupNeeded(.missingGoogleClient))
        model.enterDemo()
        #expect(model.mode == .demo)
    }
}
