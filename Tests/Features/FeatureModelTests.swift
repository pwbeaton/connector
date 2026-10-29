import Foundation
import Testing
@testable import App

struct DemoFlowTests {
    let today = CivilDate.today()

    @Test func demoSessionSyncsAndShowsTheTeam() async {
        let session = AppSession(services: .demo(today: today), options: LaunchOptions(isDemo: true))
        await session.start()
        #expect(session.phase == .main)
        #expect(session.health.records.count == SyncEngine.backfillDays)
        #expect(session.health.todayScores?.recovery.score != nil)

        let cards = session.team.cards(on: today)
        #expect(cards.count == 5)
        #expect(cards.first?.isYou == true)
        #expect(cards.first?.steps != nil, "your own uploaded numbers come back in the feed")
        let sam = cards.first { $0.member.profile.displayName == "Sam" }
        #expect(sam?.recovery == nil, "Sam keeps Recovery private")
        #expect(sam?.sleepScore != nil)
        #expect(cards.first?.reactions.first?.count == 2, "two fist bumps on your morning")
        #expect(!session.team.leaderboard.isEmpty)
    }

    @Test func onboardingWalksToToday() async {
        let session = AppSession(services: .demo(today: today, signedIn: false, inGroup: false),
                                 options: LaunchOptions(isDemo: true, screen: "welcome"))
        await session.start()
        #expect(session.phase == .onboarding)
        let onboarding = try! #require(session.onboarding)

        await onboarding.continueWithGoogle { url, _ in url }
        #expect(onboarding.step == .device)
        await onboarding.checkDevice()
        #expect(onboarding.device?.name == "Fitbit Air")
        #expect(onboarding.historyLoaded)

        onboarding.stepGoal = 10_000
        await onboarding.saveGoals()
        #expect(session.health.goals.steps == 10_000)
        #expect(onboarding.step == .group)

        onboarding.inviteCode = "camp-2345"
        await onboarding.lookUpInviteCode()
        #expect(onboarding.preview?.name == "Training Camp")
        await onboarding.joinGroup()
        #expect(onboarding.step == .sharing)

        onboarding.sharing.remove(.recovery)
        await onboarding.finish()
        #expect(session.phase == .main)
        #expect(session.team.isSharing(.recovery) == false)
        #expect(session.team.isSharing(.sleep))
    }

    @Test func aWrongInviteCodeIsExplained() async {
        let session = AppSession(services: .demo(today: today, inGroup: false),
                                 options: LaunchOptions(isDemo: true, screen: "group"))
        await session.start()
        let onboarding = try! #require(session.onboarding)
        onboarding.inviteCode = "NOPE2345"
        await onboarding.joinGroup()
        #expect(onboarding.step == .group)
        #expect(onboarding.errorMessage?.contains("No group has that code") == true)
    }

    @Test func reactionsToggle() async throws {
        let session = AppSession(services: .demo(today: today), options: LaunchOptions(isDemo: true))
        await session.start()
        let maya = try #require(session.team.cards(on: today).first { $0.member.profile.displayName == "Maya" })
        #expect(maya.reactions.first { $0.emoji == "🔥" }?.mine != nil)
        await session.team.toggleReaction("🔥", on: maya)
        let after = try #require(session.team.cards(on: today).first { $0.id == maya.id })
        #expect(after.reactions.first { $0.emoji == "🔥" } == nil)
    }

    @Test func hidingTodayRemovesItFromTheFeed() async throws {
        let session = AppSession(services: .demo(today: today), options: LaunchOptions(isDemo: true))
        await session.start()
        await session.team.setHidden(.sleep, on: today, hidden: true, today: today)
        let you = try #require(session.team.cards(on: today).first { $0.isYou })
        #expect(you.sleepScore == nil)
        #expect(you.steps != nil)
    }

    @Test func screenOptionOpensATab() async {
        let session = AppSession(services: .demo(today: today), options: LaunchOptions(isDemo: true, screen: "trends"))
        await session.start()
        #expect(session.selectedTab == .trends)
        #expect(!session.options.startsAtBottom)
    }

    @Test func bottomScreensOpenTheTabScrolledDown() {
        let options = LaunchOptions(isDemo: true, screen: "profile-bottom")
        #expect(options.tabScreen == .profile)
        #expect(options.startsAtBottom)
    }
}

struct LeaderboardTests {
    let alice = UUID(), bob = UUID(), cara = UUID()
    let day = CivilDate(year: 2026, month: 10, day: 26)

    func row(_ user: UUID, _ metric: Metric, _ value: Double, _ offset: Int = 0) -> FriendMetric {
        FriendMetric(userID: user, date: day.adding(days: offset), metric: metric, value: value, detail: [:])
    }

    func names(_ id: UUID) -> String { id == alice ? "Alice" : id == bob ? "Bob" : "Cara" }

    @Test func sumsAndRanksWithTies() {
        let rows = [row(alice, .steps, 9000), row(alice, .steps, 1000, 1), row(bob, .steps, 10_000), row(cara, .steps, 4000)]
        let board = Leaderboards.rank(rows, metric: .steps, name: names)
        #expect(board.map(\.displayName) == ["Alice", "Bob", "Cara"])
        #expect(board.map(\.rank) == [1, 1, 3])
    }

    @Test func averagesSleepAndCountsLongNights() {
        let rows = [row(alice, .sleepMinutes, 400), row(alice, .sleepMinutes, 460, 1), row(bob, .sleepMinutes, 425)]
        #expect(Leaderboards.rank(rows, metric: .averageSleep, name: names).map(\.value) == [430, 425])
        #expect(Leaderboards.rank(rows, metric: .longNights, name: names).map(\.value) == [1, 1])
    }
}

struct PromotionTests {
    func model(lastSeen: Tier?) async -> HealthModel {
        let defaults = UserDefaults(suiteName: "promotion-\(UUID().uuidString)")!
        if let lastSeen { defaults.set(lastSeen.rawValue, forKey: HealthModel.lastSeenTierKey) }
        let model = HealthModel(services: .demo(), defaults: defaults)
        await model.sync()
        return model
    }

    @Test func aHigherTierIsCelebratedOnce() async {
        let health = await model(lastSeen: .rookie)
        let tier = health.snapshot.tier.tier
        #expect(tier > .rookie, "demo data reaches at least Bronze")
        #expect(health.promotion == tier)
        health.promotion = nil
        await health.load()
        #expect(health.promotion == nil, "the same tier isn't celebrated twice")
    }

    @Test func theFirstLaunchJustRemembersTheTier() async {
        let health = await model(lastSeen: nil)
        #expect(health.promotion == nil)
    }
}

struct WeeklyRecapTests {
    @Test func summarizesTheWeekWithoutCountingMissingDays() {
        let monday = CivilDate(year: 2026, month: 10, day: 26)
        var records = DemoData.records(endingOn: monday.adding(days: 3), days: 40)
        records.removeAll { $0.date == monday.adding(days: 1) }  // Tuesday not worn
        let snapshot = Engine.run(records: records, goals: Goals(), today: monday.adding(days: 3))
        let recap = WeeklyRecap.make(snapshot: snapshot, records: records, weekStart: monday)

        let week = records.filter { $0.date >= monday }
        #expect(week.count == 3)
        #expect(recap.steps == week.compactMap(\.steps).reduce(0, +))
        let sleeps = week.compactMap { $0.sleep?.minutesAsleep }
        #expect(recap.averageSleepMinutes == Int((Double(sleeps.reduce(0, +)) / Double(sleeps.count)).rounded()))
        #expect(recap.goalsPossible <= 9)
        #expect(recap.challengesTotal == 3)
    }
}

struct SmallHelperTests {
    @Test func inviteLinks() {
        #expect(DeepLink.inviteCode(from: URL(string: "plutoapp://join/camp2345")!) == "CAMP2345")
        #expect(DeepLink.inviteCode(from: URL(string: "plutoapp://join/CAMP-2345")!) == "CAMP2345")
        #expect(DeepLink.inviteCode(from: URL(string: "plutoapp://join/short")!) == nil)
        #expect(DeepLink.inviteCode(from: URL(string: "plutoapp://settings")!) == nil)
    }

    @Test func durations() {
        #expect(Format.duration(minutes: 452) == "7h 32m")
        #expect(Format.duration(minutes: 45) == "45m")
        #expect(Format.duration(minutes: 480) == "8h")
    }

    @Test func timeAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Format.ago(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(Format.ago(now.addingTimeInterval(-4 * 60), now: now) == "4 min ago")
        #expect(Format.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3 h ago")
        #expect(Format.ago(now.addingTimeInterval(-50 * 3600), now: now) == "2 days ago")
    }
}
