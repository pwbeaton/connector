import Foundation
import Supabase

/// Signing in and out with Supabase Auth.
final class AuthRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Emits the current session right away, then again after every sign-in,
    /// sign-out, or token refresh.
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    /// Exchanges Apple's ID token for a Supabase session. `nonce` is the raw
    /// value whose SHA-256 hash was sent to Apple; Supabase checks they match.
    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    /// Apple shares the user's name only on the very first sign-in, so it is
    /// saved to the account straight away and used later to prefill the profile.
    func saveNameFromApple(_ name: PersonNameComponents) async throws {
        try await client.auth.update(
            user: UserAttributes(data: [
                "given_name": .string(name.givenName ?? ""),
                "family_name": .string(name.familyName ?? ""),
            ])
        )
    }

    /// The first name Apple shared at the first sign-in, if any.
    var givenNameFromApple: String? {
        let name = client.auth.currentUser?.userMetadata["given_name"]?.stringValue ?? ""
        return name.isEmpty ? nil : name
    }

    /// Signs out on this device only; the user's other devices stay signed in.
    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
