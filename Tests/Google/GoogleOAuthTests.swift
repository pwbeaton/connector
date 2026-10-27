import Foundation
import Testing
@testable import App

struct PKCETests {
    @Test func matchesTheRFC7636Example() {
        // RFC 7636, Appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreLongAndURLSafe() {
        let pkce = PKCE.generate()
        #expect((43...128).contains(pkce.verifier.count))
        #expect(!pkce.challenge.contains("="))
        #expect(!pkce.challenge.contains("+"))
        #expect(!pkce.challenge.contains("/"))
    }
}

struct AuthorizationRequestTests {
    private let request = AuthorizationRequest.make(
        config: testConfig, pkce: PKCE(verifier: "verifier", challenge: "challenge"), state: "state-1", rawNonce: "raw-nonce")

    @Test func urlCarriesEverythingGoogleNeeds() {
        let url = request.url
        var asRequest = URLRequest(url: url)
        asRequest.httpMethod = "GET"
        #expect(url.host() == "accounts.google.com")
        #expect(asRequest.queryValue("client_id") == testConfig.clientID)
        #expect(asRequest.queryValue("redirect_uri") == "com.googleusercontent.apps.1234-abc:/oauth2redirect")
        #expect(asRequest.queryValue("response_type") == "code")
        #expect(asRequest.queryValue("code_challenge") == "challenge")
        #expect(asRequest.queryValue("code_challenge_method") == "S256")
        #expect(asRequest.queryValue("state") == "state-1")
        // Google gets the hash; Supabase later gets the raw nonce.
        #expect(asRequest.queryValue("nonce") == Nonce.sha256("raw-nonce"))
        let scopes = asRequest.queryValue("scope")?.split(separator: " ").map(String.init) ?? []
        #expect(Set(scopes) == Set(GoogleScopes.all))
    }

    @Test func readsTheCodeFromTheRedirect() throws {
        let callback = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=state-1&code=4/abc")!
        #expect(try request.code(from: callback) == "4/abc")
    }

    @Test func rejectsAForeignState() {
        let callback = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=other&code=4/abc")!
        #expect(throws: GoogleAuthError.stateMismatch) { try request.code(from: callback) }
    }

    @Test func reportsWhenTheUserDeclines() {
        let callback = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?error=access_denied&state=state-1")!
        #expect(throws: GoogleAuthError.accessDenied) { try request.code(from: callback) }
    }

    @Test func reportsAMissingCode() {
        let callback = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=state-1")!
        #expect(throws: GoogleAuthError.missingCode) { try request.code(from: callback) }
    }
}

struct TokenTests {
    @Test func tokenResponseBecomesTokens() throws {
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(Fixtures.tokenResponse.utf8))
        let tokens = response.tokens(now: fixedNow)
        #expect(tokens.accessToken == "access-new")
        #expect(tokens.refreshToken == "refresh-new")
        #expect(tokens.expiresAt == fixedNow.addingTimeInterval(3599))
        #expect(tokens.has(GoogleScopes.sleep))
        #expect(!tokens.has(GoogleScopes.activity))
        #expect(tokens.idToken == "header.payload.signature")
    }

    @Test func refreshKeepsTheRefreshTokenAndScopes() throws {
        let json = #"{"access_token": "access-2", "expires_in": 3600, "token_type": "Bearer"}"#
        let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        let refreshed = response.tokens(now: fixedNow, previous: validTokens())
        #expect(refreshed.accessToken == "access-2")
        #expect(refreshed.refreshToken == "refresh-1")
        #expect(refreshed.grantedScopes == Set(GoogleScopes.all))
        #expect(refreshed.idToken == "id-token")
    }

    @Test func knowsWhichHealthScopesAreMissing() {
        var tokens = validTokens()
        tokens.grantedScopes.remove(GoogleScopes.sleep)
        #expect(tokens.missingHealthScopes == [GoogleScopes.sleep])
    }

    @Test func refreshesShortlyBeforeExpiry() {
        #expect(validTokens(expiresIn: 30).needsRefresh(now: fixedNow))
        #expect(!validTokens(expiresIn: 600).needsRefresh(now: fixedNow))
    }

    @Test func exchangeRequestIsAFormPost() {
        let request = TokenRequests.exchange(code: "4/abc", verifier: "v~1", config: testConfig)
        #expect(request.httpMethod == "POST")
        #expect(request.url == GoogleOAuthEndpoints.token)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = request.bodyString
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=4%2Fabc"))
        #expect(body.contains("code_verifier=v~1"))
        #expect(body.contains("client_id=1234-abc.apps.googleusercontent.com"))
        #expect(!body.contains("client_secret"))
    }
}

struct GoogleSessionTests {
    @Test func signInSavesTokens() async throws {
        let store = InMemoryTokenStore()
        let transport = StubTransport { _ in (200, Fixtures.tokenResponse) }
        let session = GoogleSession(config: testConfig, store: store, transport: transport, now: { fixedNow })
        let request = AuthorizationRequest.make(config: testConfig)

        let tokens = try await session.completeSignIn(code: "4/abc", request: request)
        #expect(tokens.accessToken == "access-new")
        #expect(store.load() == tokens)
        #expect(transport.requests.first?.bodyString.contains("code_verifier=\(request.pkce.verifier)") == true)
    }

    @Test func refreshesAnExpiredAccessToken() async throws {
        let store = InMemoryTokenStore(validTokens(expiresIn: -10))
        let transport = StubTransport { _ in (200, #"{"access_token": "access-2", "expires_in": 3600}"#) }
        let session = GoogleSession(config: testConfig, store: store, transport: transport, now: { fixedNow })

        #expect(try await session.accessToken() == "access-2")
        #expect(transport.requests.first?.bodyString.contains("grant_type=refresh_token") == true)
        #expect(store.load()?.refreshToken == "refresh-1")
    }

    @Test func usesAFreshTokenWithoutCallingGoogle() async throws {
        let transport = StubTransport { _ in (500, "") }
        let session = GoogleSession(config: testConfig, store: InMemoryTokenStore(validTokens()), transport: transport,
                                    now: { fixedNow })
        #expect(try await session.accessToken() == "access-1")
        #expect(transport.requests.isEmpty)
    }

    @Test func aRevokedRefreshTokenMeansReconnect() async throws {
        let store = InMemoryTokenStore(validTokens(expiresIn: -10))
        let transport = StubTransport { _ in (400, #"{"error": "invalid_grant"}"#) }
        let session = GoogleSession(config: testConfig, store: store, transport: transport, now: { fixedNow })

        await #expect(throws: GoogleAuthError.reconnectRequired) { try await session.accessToken() }
        #expect(store.load() == nil)
    }

    @Test func noTokensMeansReconnect() async {
        let session = GoogleSession(config: testConfig, store: InMemoryTokenStore(), transport: StubTransport { _ in (200, "") })
        await #expect(throws: GoogleAuthError.reconnectRequired) { try await session.accessToken() }
    }

    @Test func signOutRevokesAndForgets() async {
        let store = InMemoryTokenStore(validTokens())
        let transport = StubTransport { _ in (200, "") }
        let session = GoogleSession(config: testConfig, store: store, transport: transport, now: { fixedNow })
        await session.signOut()
        #expect(store.load() == nil)
        #expect(transport.requests.first?.url == GoogleOAuthEndpoints.revoke)
    }
}
