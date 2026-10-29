import Foundation
import Observation

/// Top-level app state: which mode the app runs in.
@Observable
final class AppModel {
    enum Mode: Equatable {
        /// Built-in sample data; no Google or Supabase needed.
        case demo
        /// Real data: Google Health on the phone, Supabase for friends.
        case live(AppConfig)
        /// Config/Secrets.xcconfig or the Google client ID is missing.
        case setupNeeded(AppConfig.LoadError)
    }

    let options: LaunchOptions
    private(set) var mode: Mode
    /// The signed-in (or demo) session; nil while setup is needed.
    private(set) var session: AppSession?
    /// The real configuration, kept so someone exploring sample data can go back to signing in.
    @ObservationIgnored private var liveConfig: AppConfig?
    @ObservationIgnored private let makeLiveServices: (AppConfig) -> AppServices

    init(options: LaunchOptions, loadConfig: () throws -> AppConfig = AppConfig.fromMainBundle,
         makeLiveServices: @escaping (AppConfig) -> AppServices = AppServices.live) {
        self.options = options
        self.makeLiveServices = makeLiveServices
        if options.isDemo {
            mode = .demo
            session = AppSession(services: Self.demoServices(for: options), options: options)
        } else {
            do {
                let config = try loadConfig()
                liveConfig = config
                mode = .live(config)
                session = AppSession(services: makeLiveServices(config), options: options)
            } catch let error as AppConfig.LoadError {
                mode = .setupNeeded(error)
            } catch {
                mode = .setupNeeded(.missingSecrets)
            }
        }
    }

    /// Lets someone explore the app with sample data before setting anything up
    /// (also how App Review sees the app without a Fitbit).
    func enterDemo() {
        mode = .demo
        session = AppSession(services: Self.demoServices(for: options), options: options)
    }

    /// From sample data back to the real sign-in (only when the app has a live configuration).
    func exitDemo() {
        guard let liveConfig else { return }
        mode = .live(liveConfig)
        session = AppSession(services: makeLiveServices(liveConfig), options: options)
    }

    var canExploreSampleData: Bool {
        if case .live = mode { return true }
        return false
    }

    var canExitSampleData: Bool { mode == .demo && liveConfig != nil && !options.isDemo }

    /// Demo onboarding screens start signed out and without a group, like a new user.
    private static func demoServices(for options: LaunchOptions) -> AppServices {
        let onboarding = options.screen.flatMap(OnboardingModel.Step.init(rawValue:))
        return .demo(signedIn: onboarding.map { $0 != .welcome } ?? true, inGroup: onboarding == nil)
    }
}

/// The tabs after onboarding.
/// Nonisolated so its Equatable/Hashable conformances can run anywhere: SwiftUI compares
/// `.sensoryFeedback` triggers off the main thread, and a main-actor conformance traps there.
nonisolated enum MainTab: String, CaseIterable, Hashable, Sendable {
    case today, team, trends, profile
}

extension LaunchOptions {
    /// The tab named by `-screen` ("today", or "today-bottom" to open scrolled to the end).
    var tabScreen: MainTab? {
        screen.flatMap { MainTab(rawValue: $0.replacingOccurrences(of: "-bottom", with: "")) }
    }

    /// Screenshots of the lower half of a tab use `-screen <tab>-bottom`.
    var startsAtBottom: Bool { screen?.hasSuffix("-bottom") == true }
}

/// One run of the app with its services: onboarding, then the four tabs.
@Observable
final class AppSession {
    enum Phase: Equatable {
        case loading
        case onboarding
        case main
    }

    let services: AppServices
    let options: LaunchOptions
    let health: HealthModel
    let team: TeamModel
    private(set) var phase = Phase.loading
    private(set) var onboarding: OnboardingModel?
    var selectedTab = MainTab.today
    /// Your name and photo as friends see them.
    private(set) var profile: Profile?
    /// An invite code from a link (`<scheme>://join/CODE`) waiting to be joined.
    var pendingInviteCode: String?

    static let onboardingCompleteKey = "onboardingComplete"

    init(services: AppServices, options: LaunchOptions) {
        self.services = services
        self.options = options
        // Demo mode keeps its own settings so it never affects the real account's.
        health = HealthModel(services: services,
                             defaults: services.isDemo ? UserDefaults(suiteName: "demo") ?? .standard : .standard)
        team = TeamModel(services: services)
        // The leaderboard opens on this week's group challenge.
        team.leaderboardMetric = LeaderboardMetric(Challenges.group(for: CivilDate.today().weekStart))
    }

    var isDemo: Bool { services.isDemo }

    /// Decides where to start, then loads data. Called once when the app appears.
    func start() async {
        guard phase == .loading else { return }
        await health.load()

        if let screen = options.screen, let step = OnboardingModel.Step(rawValue: screen) {
            beginOnboarding(at: step)
            if step == .goals || step == .group || step == .sharing { await health.sync() }
            return
        }

        let signedIn = await services.backend.currentUserID() != nil
        let finished = isDemo || UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)
        if !signedIn {
            beginOnboarding(at: .welcome)
        } else if !finished {
            beginOnboarding(at: .device)
        } else {
            if let tab = options.tabScreen { selectedTab = tab }
            phase = .main
            await refresh()
        }
    }

    /// Sync from the tracker, then reload friends. Runs on launch, on foreground, and on pull-to-refresh.
    func refresh() async {
        await health.sync()
        await team.refresh(today: health.today)
        if let profile = try? await services.backend.myProfile() { self.profile = profile }
    }

    func beginOnboarding(at step: OnboardingModel.Step) {
        onboarding = OnboardingModel(services: services, health: health, team: team, startAt: step,
                                     inviteCode: pendingInviteCode) { [weak self] in
            self?.finishOnboarding()
        }
        pendingInviteCode = nil
        phase = .onboarding
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        onboarding = nil
        selectedTab = .today
        phase = .main
        Task { await team.refresh(today: health.today) }
    }

    /// Handles `<scheme>://join/CODE` links from invites.
    func open(_ url: URL) {
        guard let code = DeepLink.inviteCode(from: url) else { return }
        if phase == .onboarding, let onboarding {
            onboarding.inviteCode = code
            if onboarding.step == .group { Task { await onboarding.lookUpInviteCode() } }
        } else {
            pendingInviteCode = code
            if phase == .main { selectedTab = .team }
        }
    }

    func signOut() async {
        await services.backend.signOut()
        await services.google?.session.signOut()
        await health.reset()
        UserDefaults.standard.set(false, forKey: Self.onboardingCompleteKey)
        beginOnboarding(at: .welcome)
    }

    func deleteAccount() async throws {
        try await services.backend.deleteAccount()
        await signOut()
    }

    /// Signs in to Google again after the connection expired (the friends account stays signed in).
    func reconnectGoogle(authenticate: OnboardingModel.Authenticate) async {
        guard let google = services.google else { return }
        do {
            let request = google.makeRequest()
            let callback = try await authenticate(request.url, google.callbackScheme)
            _ = try await google.complete(callback: callback, request: request)
            await refresh()
        } catch {
            // Leave the reconnect banner up; the user can try again.
        }
    }
}

/// Invite links: `<scheme>://join/CODE`.
nonisolated enum DeepLink {
    static func inviteCode(from url: URL) -> String? {
        let parts = ([url.host ?? ""] + url.pathComponents).filter { !$0.isEmpty && $0 != "/" }
        guard parts.count == 2, parts[0].lowercased() == "join", InviteCode.isComplete(parts[1]) else { return nil }
        return InviteCode.normalize(parts[1])
    }
}
