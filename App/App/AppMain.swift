import SwiftUI

/// The app's entry point.
///
/// The Swift module is named `App`, so SwiftUI's `App` protocol is written in
/// full (`SwiftUI.App`) to keep the two names from being confused.
@main
struct AppMain: SwiftUI.App {
    /// Nil when Config/Secrets.xcconfig is missing; the app then explains how to fix it.
    @State private var dependencies: Dependencies?

    init() {
        let config = try? AppConfig.fromMainBundle()
        _dependencies = State(initialValue: config.map { Dependencies(config: $0) })
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView(dependencies: dependencies)
            } else {
                MissingConfigView()
            }
        }
    }
}
