import Foundation
import Observation

/// Whether someone is signed in. RootView watches `state` to pick the screen.
@Observable
final class SessionModel {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State = .loading
    private let auth: AuthRepository

    init(auth: AuthRepository) {
        self.auth = auth
    }

    /// Follows sign-ins and sign-outs for as long as the calling task runs.
    /// Supabase emits the saved session first, so a returning user skips sign-in.
    func observe() async {
        for await change in auth.authStateChanges {
            if let session = change.session {
                state = .signedIn(userID: session.user.id)
            } else {
                state = .signedOut
            }
        }
    }

    func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            // The local session is cleared even if the server call fails,
            // and observe() will switch to the sign-in screen.
        }
    }
}
