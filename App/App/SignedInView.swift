import SwiftUI

/// After sign-in: loads the profile, asks for a name and photo if there's no
/// name yet, and otherwise shows the (placeholder) home screen.
struct SignedInView: View {
    let userID: UUID
    let dependencies: Dependencies

    @State private var profile: ProfileDTO?
    @State private var loadFailed = false
    @State private var isEditingProfile = false

    var body: some View {
        Group {
            if let profile {
                if profile.displayName.isEmpty || isEditingProfile {
                    ProfileSetupView(
                        profile: profile,
                        givenNameFromApple: dependencies.auth.givenNameFromApple,
                        profiles: dependencies.profiles
                    ) { saved in
                        self.profile = saved
                        isEditingProfile = false
                    }
                } else {
                    HomePlaceholderView(profile: profile, session: dependencies.session) {
                        isEditingProfile = true
                    }
                }
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load your profile", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: userID) { await load() }
    }

    private func load() async {
        loadFailed = false
        do {
            var loaded = try await dependencies.profiles.loadProfile(userID: userID)
            // Keep the time zone current (it changes when people travel).
            let current = TimeZone.current.identifier
            if !loaded.displayName.isEmpty, loaded.timezone != current {
                loaded = (try? await dependencies.profiles.updateProfile(
                    userID: userID, ProfileUpdate(timezone: current))) ?? loaded
            }
            profile = loaded
        } catch {
            loadFailed = true
        }
    }
}

/// Stands in for the feed until Phase 2 and 3 build the real cards.
private struct HomePlaceholderView: View {
    let profile: ProfileDTO
    let session: SessionModel
    let onEditProfile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            AvatarView(name: profile.displayName, url: profile.avatarURL, size: 96)
            Text("Hi, \(profile.displayName)")
                .font(.title.bold())
            Text("Your daily card will appear here once Apple Health is connected.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Edit profile", action: onEditProfile)
                .buttonStyle(.primary)
            Button("Sign out") {
                Task { await session.signOut() }
            }
            .frame(minHeight: Theme.buttonHeight)
        }
        .padding(Theme.screenPadding)
    }
}
