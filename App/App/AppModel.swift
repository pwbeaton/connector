import Foundation
import Observation

/// Top-level app state: which mode the app runs in.
@Observable
final class AppModel {
    enum Mode: Equatable {
        /// Built-in sample data; no Google or Supabase needed.
        case demo
        /// Real data: Google Health on the phone, Supabase for friends.
        case live(AppConfig)
        /// Config/Secrets.xcconfig or the Google client ID is missing.
        case setupNeeded(AppConfig.LoadError)
    }

    let options: LaunchOptions
    private(set) var mode: Mode

    init(options: LaunchOptions, loadConfig: () throws -> AppConfig = AppConfig.fromMainBundle) {
        self.options = options
        if options.isDemo {
            mode = .demo
        } else {
            do {
                mode = .live(try loadConfig())
            } catch let error as AppConfig.LoadError {
                mode = .setupNeeded(error)
            } catch {
                mode = .setupNeeded(.missingSecrets)
            }
        }
    }

    /// Lets someone explore the app with sample data before setting anything up.
    func enterDemo() {
        mode = .demo
    }
}
