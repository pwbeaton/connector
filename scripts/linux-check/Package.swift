// swift-tools-version: 6.2
// Linux mirror of the app's platform-neutral code, for fast local type-checking and tests.
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "SwiftCheck",
    dependencies: [.package(path: "swift-crypto")],
    targets: [
        .target(name: "App", dependencies: [.product(name: "Crypto", package: "swift-crypto")],
                path: "Sources/App", swiftSettings: settings),
        .testTarget(name: "AppTests", dependencies: ["App"], path: "Tests/AppTests", swiftSettings: settings),
    ],
    swiftLanguageModes: [.v6]
)
