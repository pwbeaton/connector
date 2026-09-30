import AuthenticationServices
import Foundation
import Observation

/// Drives the Sign in with Apple button: prepares Apple's request, then trades
/// Apple's ID token for a Supabase session.
@Observable
final class SignInModel {
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let auth: AuthRepository
    /// The raw nonce for the request in flight; Apple only ever sees its hash.
    private var currentNonce: String?

    init(auth: AuthRepository) {
        self.auth = auth
    }

    /// Called by the button just before Apple's sheet appears.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(nonce)
    }

    /// Called by the button when Apple's sheet closes.
    func handle(_ result: Result<ASAuthorization, any Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            // Closing the sheet on purpose isn't an error worth showing.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Sign in with Apple didn't finish. Please try again."
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Apple didn't return a sign-in token. Please try again."
                return
            }
            let name = credential.fullName
            Task { await signIn(idToken: idToken, nonce: nonce, name: name) }
        }
    }

    private func signIn(idToken: String, nonce: String, name: PersonNameComponents?) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce, name: name)
        } catch {
            errorMessage = "We couldn't sign you in. Check your connection and try again."
        }
    }
}
