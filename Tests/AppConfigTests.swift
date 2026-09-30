import Foundation
import Testing
@testable import App

struct AppConfigTests {
    @Test func loadsValidValues() throws {
        let config = try AppConfig.load(from: [
            "SupabaseURL": "https://abcd1234.supabase.co",
            "SupabaseAnonKey": "sb_publishable_123",
        ])
        #expect(config.supabaseURL == URL(string: "https://abcd1234.supabase.co"))
        #expect(config.supabaseKey == "sb_publishable_123")
    }

    @Test func acceptsLocalStack() throws {
        let config = try AppConfig.load(from: [
            "SupabaseURL": "http://127.0.0.1:54321",
            "SupabaseAnonKey": "local-key",
        ])
        #expect(config.supabaseURL.port == 54321)
    }

    @Test func missingSecretsFileIsReported() {
        // Without Secrets.xcconfig the build settings expand to empty strings.
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: ["SupabaseURL": "", "SupabaseAnonKey": ""])
        }
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: [:])
        }
    }

    @Test func exampleValuesAreReportedAsMissing() {
        #expect(throws: AppConfig.LoadError.missingSecrets) {
            try AppConfig.load(from: [
                "SupabaseURL": "https://your-project-ref.supabase.co",
                "SupabaseAnonKey": "your-anon-or-publishable-key",
            ])
        }
    }

    @Test func urlWithoutSchemeIsRejected() {
        // What you get if the "https:/$()/" trick is left out of the xcconfig.
        #expect(throws: AppConfig.LoadError.invalidURL("https:")) {
            try AppConfig.load(from: ["SupabaseURL": "https:", "SupabaseAnonKey": "key"])
        }
    }
}
