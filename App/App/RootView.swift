import SwiftUI

/// Decides which screen the app shows. Sign-in and onboarding routing arrive in
/// the next steps of Phase 1.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming soon",
            systemImage: "heart.text.square",
            description: Text("Your group's sleep and activity, side by side.")
        )
    }
}

#Preview {
    RootView()
}
