import Foundation

/// Settings read from the app's Info.plist. Xcode fills them in at build time
/// from Config/Identity.xcconfig and the git-ignored Config/Secrets.xcconfig.
nonisolated struct AppConfig: Equatable, Sendable {
    let supabaseURL: URL
    let supabaseKey: String

    enum LoadError: Error, Equatable {
        /// Config/Secrets.xcconfig is missing, empty, or still has the example values.
        case missingSecrets
        /// SUPABASE_URL isn't a usable http(s) URL.
        case invalidURL(String)
    }

    /// Reads the settings from an Info.plist dictionary.
    static func load(from info: [String: Any]) throws -> AppConfig {
        let urlString = (info["SupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["SupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)

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
        return AppConfig(supabaseURL: url, supabaseKey: key)
    }

    static func fromMainBundle() throws -> AppConfig {
        try load(from: Bundle.main.infoDictionary ?? [:])
    }
}
