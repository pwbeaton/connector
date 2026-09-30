import Foundation
import Supabase

/// Everything the screens need, created once at launch and handed down.
/// Keeping it in one place makes it easy to see what the app talks to.
final class Dependencies {
    let auth: AuthRepository
    let profiles: ProfileRepository
    let session: SessionModel

    init(config: AppConfig) {
        let client = SupabaseService.makeClient(config: config)
        auth = AuthRepository(client: client)
        profiles = ProfileRepository(client: client)
        session = SessionModel(auth: auth)
    }
}
