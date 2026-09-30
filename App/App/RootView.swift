import SwiftUI

/// Decides which screen the app shows, based on whether someone is signed in.
struct RootView: View {
    let dependencies: Dependencies

    var body: some View {
        Group {
            switch dependencies.session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView(auth: dependencies.auth)
            case .signedIn(let userID):
                SignedInView(userID: userID, dependencies: dependencies)
            }
        }
        .task { await dependencies.session.observe() }
    }
}

/// Shown when the Supabase settings are missing from the build.
struct MissingConfigView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Setup needed", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig, add your Supabase URL and anon key, then run xcodegen generate and build again.")
        }
    }
}
