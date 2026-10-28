import SwiftUI

/// Decides which screen the app shows.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                // A new identity per session, so switching to or from sample data starts the
                // new session (its .task) and resets screen state instead of reusing the old view.
                SessionView(session: session)
                    .id(ObjectIdentifier(session))
            } else if case .setupNeeded(let reason) = model.mode {
                SetupNeededView(reason: reason) { model.enterDemo() }
            }
        }
        .tint(Theme.teal)
        .font(.archivo(17))
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
        ZStack(alignment: .bottom) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                screen(tab)
                    .opacity(session.selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(session.selectedTab == tab)
                    .accessibilityHidden(session.selectedTab != tab)
            }
            LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                                   .init(color: Theme.background.opacity(0.94), location: 0.55),
                                   .init(color: Theme.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 132)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
            PlutoTabBar(selection: Binding(get: { session.selectedTab }, set: { session.selectedTab = $0 }))
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder private func screen(_ tab: MainTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .team: TeamView()
        case .trends: TrendsView()
        case .profile: ProfileView()
        }
    }
}

/// The floating navy bar with four tabs (it turns light in dark mode).
struct PlutoTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 19, weight: .regular))
                        Text(tab.title).font(.archivo(11, .semibold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(selected ? Theme.navActiveText : Theme.navInactive)
                    .background(selected ? Theme.navActive : .clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 64)
        .background(Theme.navBackground, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color(light: 0x0C1B26, dark: 0x2A3943), lineWidth: 1))
        .shadow(color: Color(light: 0x0C1B26, dark: 0x000000).opacity(0.25), radius: 14, y: 12)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension MainTab {
    var title: String {
        switch self {
        case .today: "Today"
        case .team: "Team"
        case .trends: "Trends"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .team: "person.2"
        case .trends: "chart.bar"
        case .profile: "person"
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
                .font(.app(size: 48))
                .foregroundStyle(Theme.effort)
                .accessibilityHidden(true)
            Text("Setup needed").font(.app(.title, .bold)).foregroundStyle(Theme.textPrimary)
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
