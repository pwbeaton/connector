import Foundation
import Security

/// Sends HTTP requests. The real one uses URLSession; tests use a stub.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Where Google tokens are kept between launches.
nonisolated protocol TokenStoring: Sendable {
    func load() -> GoogleTokens?
    func save(_ tokens: GoogleTokens) throws
    func delete()
}

/// Stores tokens in the Keychain, readable after the first unlock so background
/// refresh works while the phone is locked.
nonisolated struct KeychainTokenStore: TokenStoring {
    var service = (Bundle.main.bundleIdentifier ?? "app") + ".google"
    var account = "tokens"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> GoogleTokens? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    func save(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Owns the Google tokens: saves them, refreshes them before they expire, and
/// reports when the user has to reconnect. An actor, so concurrent requests
/// never refresh twice at once.
actor GoogleSession {
    private let config: GoogleOAuthConfig
    private let store: any TokenStoring
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var tokens: GoogleTokens?

    init(config: GoogleOAuthConfig, store: any TokenStoring = KeychainTokenStore(),
         transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { .now }) {
        self.config = config
        self.store = store
        self.transport = transport
        self.now = now
        self.tokens = store.load()
    }

    var currentTokens: GoogleTokens? { tokens }
    var isConnected: Bool { tokens?.refreshToken != nil || tokens.map { !$0.needsRefresh(now: now()) } == true }

    /// Finishes sign-in: trades the authorization code for tokens and saves them.
    func completeSignIn(code: String, request: AuthorizationRequest) async throws -> GoogleTokens {
        let response = try await tokenCall(TokenRequests.exchange(code: code, verifier: request.pkce.verifier, config: config))
        let newTokens = response.tokens(now: now())
        guard newTokens.idToken != nil else { throw GoogleAuthError.missingIDToken }
        try store.save(newTokens)
        tokens = newTokens
        return newTokens
    }

    /// A usable access token, refreshing first if it's about to expire.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw GoogleAuthError.reconnectRequired }
        if !forceRefresh && !current.needsRefresh(now: now()) {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken else { throw GoogleAuthError.reconnectRequired }
        let response = try await tokenCall(TokenRequests.refresh(refreshToken: refreshToken, config: config))
        let refreshed = response.tokens(now: now(), previous: current)
        try store.save(refreshed)
        tokens = refreshed
        return refreshed.accessToken
    }

    /// Disconnects: tells Google to revoke access (best effort) and forgets the tokens.
    func signOut() async {
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            _ = try? await transport.send(TokenRequests.revoke(token: token))
        }
        store.delete()
        tokens = nil
    }

    private func tokenCall(_ request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            // invalid_grant: the refresh token was revoked or expired.
            let body = String(decoding: data, as: UTF8.self)
            if body.contains("invalid_grant") {
                store.delete()
                tokens = nil
                throw GoogleAuthError.reconnectRequired
            }
            throw GoogleAuthError.http(status: response.statusCode)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
