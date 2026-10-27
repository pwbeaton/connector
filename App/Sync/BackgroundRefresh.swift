import BackgroundTasks
import Foundation

/// Background refresh: iOS wakes the app now and then (it decides when, usually
/// a few times a day) so friends and the widget see fresh numbers. It's
/// best-effort; opening the app always syncs.
///
/// The identifier is listed in Info.plist (BGTaskSchedulerPermittedIdentifiers),
/// and AppMain handles it with SwiftUI's `.backgroundTask(.appRefresh(...))`.
nonisolated enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "app") + ".refresh" }

    /// Asks iOS to wake the app again in about `delay` (not sooner).
    static func schedule(after delay: TimeInterval = 2 * 3600) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        // Fails in the simulator and when background refresh is off; both are fine.
        try? BGTaskScheduler.shared.submit(request)
    }
}
