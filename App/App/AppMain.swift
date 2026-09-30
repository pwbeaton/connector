import SwiftUI

/// The app's entry point.
///
/// The Swift module is named `App`, so SwiftUI's `App` protocol is written in
/// full (`SwiftUI.App`) to keep the two names from being confused.
@main
struct AppMain: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
