import SwiftUI

/// Decides which screen the app shows.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                SessionView(session: session)
            } else if case .setupNeeded(let reason) = model.mode {
                SetupNeededView(reason: reason) { model.enterDemo() }
            }
        }
        .tint(Theme.effort)
        .environment(\.animatesScores, !model.options.isScreenshotMode)
        .environment(\.exploreSampleData, exploreSampleData)
        .environment(\.exitSampleData, exitSampleData)
    }

    private var exploreSampleData: (@MainActor () -> Void)? {
        guard model.canExploreSampleData else { return nil }
        let model = model
        return { model.enterDemo() }
    }

    private var exitSampleData: (@MainActor () -> Void)? {
        guard model.canExitSampleData else { return nil }
        let model = model
        return { model.exitDemo() }
    }
}

extension EnvironmentValues {
    /// Switches to built-in sample data (shown on the welcome screen of a live build).
    @Entry var exploreSampleData: (@MainActor () -> Void)?
    /// Leaves sample data for the real sign-in.
    @Entry var exitSampleData: (@MainActor () -> Void)?
}

/// Onboarding or the four tabs, for one session.
struct SessionView: View {
    let session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            case .onboarding:
                if let onboarding = session.onboarding {
                    OnboardingView(model: onboarding)
                }
            case .main:
                MainTabView()
            }
        }
        .environment(session)
        .task { await session.start() }
        .onOpenURL { session.open($0) }
    }
}

struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session
        TabView(selection: $session.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle.fill") }
                .tag(MainTab.today)
            TeamView()
                .tabItem { Label("Team", systemImage: "person.3.fill") }
                .tag(MainTab.team)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
                .tag(MainTab.trends)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(MainTab.profile)
        }
    }
}

/// Shown when the build is missing Supabase or Google settings.
struct SetupNeededView: View {
    let reason: AppConfig.LoadError
    let onExploreDemo: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(Theme.effort)
                .accessibilityHidden(true)
            Text("Setup needed").font(.title.bold()).foregroundStyle(Theme.textPrimary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Explore with sample data", action: onExploreDemo)
                .buttonStyle(.primary)
        }
        .padding(Theme.screenPadding)
        .background(Theme.background)
    }

    private var message: String {
        switch reason {
        case .missingSecrets, .invalidURL:
            "Add your Supabase URL and anon key to Config/Secrets.xcconfig (see docs/DEVICE-SETUP.md), then build again."
        case .missingGoogleClient:
            "Add your Google iOS client ID to Config/Identity.xcconfig (see docs/SETUP-GOOGLE.md), then build again."
        }
    }
}
