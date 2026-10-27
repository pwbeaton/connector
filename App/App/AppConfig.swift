import Foundation

/// Settings read from the app's Info.plist. Xcode fills them in at build time
/// from Config/Identity.xcconfig and the git-ignored Config/Secrets.xcconfig.
nonisolated struct AppConfig: Equatable, Sendable {
    let supabaseURL: URL
    let supabaseKey: String
    /// The iOS OAuth client ID from Google Cloud (public; iOS clients have no secret).
    let googleClientID: String
    /// The reversed client ID Google redirects to after sign-in.
    let googleRedirectScheme: String
    /// The app's own scheme for invite links (<scheme>://join/CODE).
    let appURLScheme: String

    nonisolated enum LoadError: Error, Equatable {
        /// Config/Secrets.xcconfig is missing, empty, or still has the example values.
        case missingSecrets
        /// SUPABASE_URL isn't a usable http(s) URL.
        case invalidURL(String)
        /// GOOGLE_CLIENT_ID_PREFIX in Config/Identity.xcconfig is still the placeholder.
        case missingGoogleClient
    }

    /// Reads the settings from an Info.plist dictionary.
    static func load(from info: [String: Any]) throws -> AppConfig {
        func value(_ key: String) -> String {
            (info[key] as? String ?? "").trimmingCharacters(in: .whitespaces)
        }
        let urlString = value("SupabaseURL")
        let key = value("SupabaseAnonKey")
        let isExampleValue = urlString.contains("your-project-ref") || key.hasPrefix("your-")
        guard !urlString.isEmpty, !key.isEmpty, !isExampleValue else {
            throw LoadError.missingSecrets
        }
        guard let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http",
              url.host() != nil
        else {
            throw LoadError.invalidURL(urlString)
        }

        let clientID = value("GoogleClientID")
        let redirectScheme = value("GoogleRedirectScheme")
        guard !clientID.isEmpty, !clientID.hasPrefix("placeholder."), !redirectScheme.isEmpty else {
            throw LoadError.missingGoogleClient
        }

        return AppConfig(
            supabaseURL: url,
            supabaseKey: key,
            googleClientID: clientID,
            googleRedirectScheme: redirectScheme,
            appURLScheme: value("AppURLScheme")
        )
    }

    static func fromMainBundle() throws -> AppConfig {
        try load(from: Bundle.main.infoDictionary ?? [:])
    }
}
