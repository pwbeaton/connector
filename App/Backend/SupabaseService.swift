import Foundation
import Supabase

/// Creates the one Supabase client the app uses.
enum SupabaseService {
    static func makeClient(config: AppConfig) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseKey,
            options: SupabaseClientOptions(
                // Use the session saved in the Keychain immediately at launch,
                // without waiting for the network. The SDK refreshes it as needed.
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }
}
