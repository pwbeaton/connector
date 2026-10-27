import CryptoKit
import Foundation

/// The Google OAuth pieces that don't need a screen: PKCE, the sign-in URL,
/// reading the redirect, and the token endpoint requests. Kept pure so tests
/// can check every detail.
///
/// Flow: Google OAuth 2.0 for iOS apps (an iOS client has no secret).
/// 1. Open `AuthorizationRequest.url` in Apple's sign-in browser.
/// 2. Google redirects to `<reversed client id>:/oauth2redirect?code=…&state=…`.
/// 3. Exchange the code (plus the PKCE verifier) for tokens.

nonisolated enum GoogleOAuthEndpoints {
    static let authorize = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
}

nonisolated enum GoogleScopes {
    /// For the account (name, email, photo, and the ID token Supabase verifies).
    static let identity = ["openid", "email", "profile"]
    /// Read-only Google Health access.
    static let health = [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.profile.readonly",
        "https://www.googleapis.com/auth/googlehealth.settings.readonly",
    ]
    static let all = identity + health

    static let activity = health[0]
    static let sleep = health[1]
    static let healthMetrics = health[2]
    static let profile = health[3]
    static let settings = health[4]
}

nonisolated struct GoogleOAuthConfig: Equatable, Sendable {
    let clientID: String
    /// The reversed client ID, e.g. com.googleusercontent.apps.1234-abc.
    let redirectScheme: String

    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
}

/// PKCE (RFC 7636): proves the app that started sign-in is the one finishing it.
nonisolated struct PKCE: Equatable, Sendable {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        let verifier = Nonce.random(length: 64)
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    /// BASE64URL(SHA256(verifier)) without padding (the "S256" method).
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One sign-in attempt: the URL to open plus the secrets needed to finish it.
nonisolated struct AuthorizationRequest: Sendable {
    let url: URL
    let state: String
    let pkce: PKCE
    /// Raw nonce: Google gets its SHA-256 inside the URL; Supabase gets this value.
    let rawNonce: String

    static func make(config: GoogleOAuthConfig, scopes: [String] = GoogleScopes.all, loginHint: String? = nil,
                     pkce: PKCE = .generate(), state: String = Nonce.random(), rawNonce: String = Nonce.random()) -> AuthorizationRequest {
        var components = URLComponents(url: GoogleOAuthEndpoints.authorize, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: Nonce.sha256(rawNonce)),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = items
        return AuthorizationRequest(url: components.url!, state: state, pkce: pkce, rawNonce: rawNonce)
    }

    /// Reads the authorization code from Google's redirect.
    func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? GoogleAuthError.accessDenied : GoogleAuthError.server(error)
        }
        guard value("state") == state else { throw GoogleAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw GoogleAuthError.missingCode }
        return code
    }
}

nonisolated enum GoogleAuthError: Error, Equatable {
    case cancelled
    case accessDenied
    case stateMismatch
    case missingCode
    case missingIDToken
    /// The refresh token was revoked or expired: the user must reconnect.
    case reconnectRequired
    case server(String)
    case http(status: Int)
}

/// Tokens from Google, saved in the Keychain.
nonisolated struct GoogleTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var expiresAt: Date
    var refreshToken: String?
    var grantedScopes: Set<String>
    var idToken: String?

    /// True when the access token expires within a minute.
    func needsRefresh(now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) < 60
    }

    /// Health scopes the user unticked on Google's consent screen.
    var missingHealthScopes: [String] {
        GoogleScopes.health.filter { !grantedScopes.contains($0) }
    }

    func has(_ scope: String) -> Bool { grantedScopes.contains(scope) }
}

/// The token endpoint's JSON.
nonisolated struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
    }

    /// Merges into existing tokens (a refresh response has no refresh token or ID token).
    func tokens(now: Date = .now, previous: GoogleTokens? = nil) -> GoogleTokens {
        GoogleTokens(
            accessToken: accessToken,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)),
            refreshToken: refreshToken ?? previous?.refreshToken,
            grantedScopes: scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previous?.grantedScopes ?? [],
            idToken: idToken ?? previous?.idToken
        )
    }
}

nonisolated enum TokenRequests {
    static func exchange(code: String, verifier: String, config: GoogleOAuthConfig) -> URLRequest {
        form(GoogleOAuthEndpoints.token, [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI,
        ])
    }

    static func refresh(refreshToken: String, config: GoogleOAuthConfig) -> URLRequest {
        form(GoogleOAuthEndpoints.token, [
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    static func revoke(token: String) -> URLRequest {
        form(GoogleOAuthEndpoints.revoke, ["token": token])
    }

    private static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}
