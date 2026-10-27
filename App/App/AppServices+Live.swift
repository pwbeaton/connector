import Foundation
import Supabase

extension AppServices {
    /// The real app: Google Health on the phone, Supabase for friends.
    static func live(config: AppConfig) -> AppServices {
        let googleConfig = GoogleOAuthConfig(clientID: config.googleClientID, redirectScheme: config.googleRedirectScheme)
        let session = GoogleSession(config: googleConfig)
        let source = GoogleHealthSource(client: GoogleHealthClient(session: session))
        let backend = SupabaseBackend(client: SupabaseService.makeClient(config: config))
        let store = DayStore.standard()
        return AppServices(backend: backend, store: store, source: source,
                           sync: SyncEngine(source: source, store: store, uploader: backend, widget: WidgetBridge()),
                           google: GoogleSignIn(config: googleConfig, session: session))
    }
}
