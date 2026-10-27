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

/// Where files shared by the app and the widget live.
nonisolated enum SharedFiles {
    /// The App Group container, or the app's own Application Support folder when the
    /// App Group isn't available (unsigned simulator builds, tests).
    static func directory(appGroup: String? = AppGroup.identifier) -> URL {
        if let appGroup, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return container
        }
        return URL.applicationSupportDirectory
    }
}
