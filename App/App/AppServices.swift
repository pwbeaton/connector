import Foundation

/// Everything the screens talk to, built once per session. Demo mode swaps in
/// sample data but runs the same sync, scoring, and team code as the real app.
nonisolated struct AppServices: Sendable {
    let backend: any Backend
    let store: DayStore
    let source: any HealthDataSource
    let sync: SyncEngine
    /// Google sign-in; nil in demo mode.
    let google: GoogleSignIn?

    var isDemo: Bool { google == nil }

    /// Sample data: a fresh store each launch, four demo friends, nothing sent anywhere.
    static func demo(today: CivilDate = .today(), signedIn: Bool = true, inGroup: Bool = true) -> AppServices {
        let backend = DemoBackend(today: today, signedIn: signedIn, inGroup: inGroup)
        let store = DayStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-\(UUID().uuidString).json"))
        let source = DemoHealthSource(today: today)
        return AppServices(backend: backend, store: store, source: source,
                           sync: SyncEngine(source: source, store: store, uploader: backend), google: nil)
    }
}

/// "Continue with Google": opens Google's sign-in page, then trades the result for tokens.
nonisolated struct GoogleSignIn: Sendable {
    let config: GoogleOAuthConfig
    let session: GoogleSession

    var callbackScheme: String { config.redirectScheme }

    func makeRequest() -> AuthorizationRequest {
        AuthorizationRequest.make(config: config)
    }

    /// Finishes sign-in with the URL Google redirected back to.
    func complete(callback: URL, request: AuthorizationRequest) async throws -> GoogleTokens {
        try await session.completeSignIn(code: request.code(from: callback), request: request)
    }
}
