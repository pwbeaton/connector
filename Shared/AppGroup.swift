import Foundation

/// The App Group that lets the app and the widget share files.
///
/// The identifier is set once in Config/Identity.xcconfig and copied into each
/// target's Info.plist under the `AppGroupID` key.
nonisolated enum AppGroup {
    static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
