import Testing
@testable import App

struct AppGroupTests {
    /// Proves the chain Identity.xcconfig → build settings → Info.plist works.
    @Test func identifierComesFromBuildSettings() {
        let identifier = AppGroup.identifier
        #expect(identifier?.hasPrefix("group.") == true)
    }
}
