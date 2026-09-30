import Foundation
import Supabase

/// Signing in and out with Supabase Auth.
final class AuthRepository {
    private let client: SupabaseClient
    private var appleGivenName: String?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Emits the current session right away, then again after every sign-in,
    /// sign-out, or token refresh.
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    /// Exchanges Apple's ID token for a Supabase session. `nonce` is the raw
    /// value whose SHA-256 hash was sent to Apple; Supabase checks they match.
    ///
    /// Apple shares the user's name only on the very first sign-in, so it is
    /// kept in memory before the session starts (the profile screen appears as
    /// soon as it does) and then saved to the account for later.
    func signInWithApple(idToken: String, nonce: String, name: PersonNameComponents?) async throws {
        // Reset on every sign-in so a different person on this phone never
        // inherits the previous person's name.
        appleGivenName = name?.givenName.flatMap { $0.isEmpty ? nil : $0 }
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        if let name, name.givenName != nil || name.familyName != nil {
            try? await client.auth.update(
                user: UserAttributes(data: [
                    "given_name": .string(name.givenName ?? ""),
                    "family_name": .string(name.familyName ?? ""),
                ])
            )
        }
    }

    /// The first name Apple shared at the first sign-in, if any.
    var givenNameFromApple: String? {
        if let appleGivenName { return appleGivenName }
        let saved = client.auth.currentUser?.userMetadata["given_name"]?.stringValue ?? ""
        return saved.isEmpty ? nil : saved
    }

    /// Signs out on this device only; the user's other devices stay signed in.
    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
