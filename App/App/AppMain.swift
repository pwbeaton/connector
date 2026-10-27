import SwiftUI

/// The app's entry point.
///
/// The Swift module is named `App`, so SwiftUI's `App` protocol is written in
/// full (`SwiftUI.App`) to keep the two names from being confused.
@main
struct AppMain: SwiftUI.App {
    @State private var model = AppModel(options: .from(.standard))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase) {
            guard let session = model.session, session.phase == .main else { return }
            switch scenePhase {
            case .active:
                // Opening the app always syncs.
                Task { await session.refresh() }
            case .background:
                if !session.isDemo { BackgroundRefresh.schedule() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [model] in
            await Self.backgroundSync(model)
            BackgroundRefresh.schedule()
        }
    }

    /// Runs when iOS wakes the app in the background: sync, which also updates the widget.
    private static func backgroundSync(_ model: AppModel) async {
        // The window may never appear during a background launch, so don't wait for the session to start.
        guard let session = model.session, !session.isDemo,
              await session.services.backend.currentUserID() != nil else { return }
        await session.health.sync()
    }
}
