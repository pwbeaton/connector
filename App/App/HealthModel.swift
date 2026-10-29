import Foundation
import Observation

/// Your own numbers: the day records on this iPhone, the scores computed from
/// them, and the state of the last sync. Today, Trends, and Profile read it.
@Observable
final class HealthModel {
    private(set) var state = LocalState()
    private(set) var snapshot: EngineSnapshot
    private(set) var isSyncing = false
    private(set) var lastReport: SyncReport?
    /// Biological age for every day with enough data (recomputed on each load).
    private(set) var biologicalAges: [CivilDate: BiologicalAgeResult] = [:]
    /// Set when the training tier went up since the app last showed it (a moment to celebrate).
    var promotion: Tier?
    /// True while waiting for the tracker to sync through the Google Health app (see `waitForTrackerSync`).
    private(set) var isWaitingForTracker = false

    private let services: AppServices
    private let defaults: UserDefaults
    static let lastSeenTierKey = "lastSeenTier"

    init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        snapshot = Engine.run(records: [], goals: Goals(), today: .today())
    }

    var today: CivilDate { snapshot.today }
    var goals: Goals { state.goals }
    var records: [DayRecord] { state.records }
    var todayRecord: DayRecord? { state.records.last { $0.date == today } }
    var todayScores: DayScores? { snapshot.todayScores }
    var device: DeviceStatus? { state.device }
    var hasData: Bool { !state.records.isEmpty }
    var needsReconnect: Bool { lastReport?.status == .reconnectRequired }

    /// A short message when the last sync didn't fully work.
    var syncProblem: String? {
        switch lastReport?.status {
        case .failed(let message): message
        case .reconnectRequired: "Your Fitbit connection expired. Reconnect to keep syncing."
        default: lastReport?.uploadError
        }
    }

    // MARK: Tracker sync

    /// The Fitbit Air can't talk to other apps: it syncs only with the Google Health app, which
    /// uploads to Google, which Pluto reads. Google's documented link to open that app on Today
    /// (it syncs the tracker when opened). Falls back to Fitbit's website if it isn't installed.
    static let googleHealthAppURL = URL(string: "https://www.fitbit.com/in-app/today")!
    /// The tracker syncs every 15 minutes while Google Health runs in the background, so an hour
    /// without a sync means it needs a nudge.
    static let trackerStaleAfter: TimeInterval = 60 * 60

    /// Whether the tracker hasn't reached Google recently (never in sample data).
    func isTrackerStale(now: Date = .now) -> Bool {
        guard !services.isDemo, let device else { return false }
        guard let lastSync = device.lastSync else { return true }
        return now.timeIntervalSince(lastSync) > Self.trackerStaleAfter
    }

    /// Call when sending the user to the Google Health app. Polls Google every 10 seconds (it
    /// carries on when they come back) until the tracker's new sync shows up, then once more a
    /// little later, because sleep and HRV can land after the device's sync time. Gives up after
    /// about 3 minutes.
    func waitForTrackerSync() {
        guard !isWaitingForTracker else { return }
        let baseline = device?.lastSync ?? .distantPast
        isWaitingForTracker = true
        Task {
            defer { isWaitingForTracker = false }
            for _ in 0..<18 {
                try? await Task.sleep(for: .seconds(10))
                await sync()
                if let lastSync = device?.lastSync, lastSync > baseline {
                    try? await Task.sleep(for: .seconds(15))
                    await sync()
                    return
                }
            }
        }
    }

    /// Reads what's saved on the phone and recomputes every score.
    func load() async {
        state = await services.store.load()
        snapshot = Engine.run(records: state.records, goals: state.goals, today: .today())
        biologicalAges = BiologicalAge.timeline(records: state.records, age: chronologicalAge, sex: state.sex,
                                                today: snapshot.today)
        checkForPromotion()
    }

    /// Compares the tier with the last one shown. The first time, it just remembers it.
    private func checkForPromotion() {
        guard hasData, !snapshot.tier.isCalibrating else { return }
        let tier = snapshot.tier.tier
        let lastSeen = defaults.string(forKey: Self.lastSeenTierKey).flatMap(Tier.init(rawValue:))
        if let lastSeen, tier > lastSeen { promotion = tier }
        defaults.set(tier.rawValue, forKey: Self.lastSeenTierKey)
    }

    /// Pulls fresh data from the tracker (via Google Health) and shares the daily summaries.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastReport = await services.sync.sync()
        await load()
        isSyncing = false
    }

    func updateGoals(_ goals: Goals) async {
        _ = try? await services.store.update { $0.goals = goals }
        await load()
        try? await services.backend.updateGoals(goals)
        // Sleep and step goals change scores, so share the new ones.
        lastReport = await services.sync.sync()
        await load()
    }

    /// Forgets everything on the phone (sign-out or account deletion).
    func reset() async {
        try? await services.store.reset()
        defaults.removeObject(forKey: Self.lastSeenTierKey)
        lastReport = nil
        promotion = nil
        await load()
    }

    // MARK: Day pages

    /// Every day you can swipe back to: from the first synced day (at most 90 days ago) through today.
    var browsableDates: [CivilDate] {
        let earliest = today.adding(days: -(SyncEngine.backfillDays - 1))
        let first = max(earliest, state.records.first?.date ?? today)
        return first.through(today)
    }

    func record(on date: CivilDate) -> DayRecord? {
        state.records.last { $0.date == date }
    }

    func scores(on date: CivilDate) -> DayScores? {
        snapshot.scores(on: date)
    }

    /// Change in a score from the day before `date`.
    func dayChange(_ kind: ScoreKind, on date: CivilDate) -> Int? {
        ScoreTrend.dayChange(kind, on: date, scores: snapshot.days)
    }

    func weekComparison(_ kind: ScoreKind, endingOn date: CivilDate) -> ScoreTrend.WeekComparison? {
        ScoreTrend.weekComparison(kind, endingOn: date, scores: snapshot.days)
    }

    /// Tonight's sleep tip, based on the night that ended on `date`.
    func sleepTip(on date: CivilDate) -> SleepTip? {
        guard let sleep = record(on: date)?.sleep, let score = scores(on: date)?.sleep else { return nil }
        let recent = state.records.filter { $0.date < date && $0.date >= date.adding(days: -7) }.compactMap(\.sleep)
        return SleepTip.make(sleep: sleep, score: score, goalMinutes: goals.sleepMinutes,
                             recentWakeMinutes: recent.map(\.wakeMinuteOfDay),
                             recentAwakeMinutes: recent.map { max(0, $0.minutesInBed - $0.minutesAsleep) },
                             plannedBedtime: bedtimePlan(on: date)?.bedtime)
    }

    /// Sleep owed on the morning of `date` (14 nights, recent ones weighted more).
    func sleepDebt(on date: CivilDate) -> SleepDebt? {
        SleepDebt.compute(on: date, records: state.records, goalMinutes: goals.sleepMinutes)
    }

    /// The bedtime for the night after `date`, including a slice of any sleep debt.
    func bedtimePlan(on date: CivilDate) -> BedtimePlan? {
        BedtimePlan.make(on: date, records: state.records, goalMinutes: goals.sleepMinutes, debt: sleepDebt(on: date))
    }

    // MARK: Biological age

    /// The age biological age is compared with: what you typed in, else your Google Health profile age.
    var chronologicalAge: Int? { state.ageOverride ?? state.profileAge }
    var profileAge: Int? { state.profileAge }
    var sex: BiologicalSex? { state.sex }

    func biologicalAge(on date: CivilDate) -> BiologicalAgeResult? {
        biologicalAges[date]
    }

    func biologicalAgeTrend(on date: CivilDate) -> BiologicalAgeTrend? {
        BiologicalAge.trend(on: date, in: biologicalAges)
    }

    /// Saves the age and sex used for biological age (nil age falls back to the profile age).
    func updateBiologicalAgeSettings(ageOverride: Int?, sex: BiologicalSex?) async {
        _ = try? await services.store.update { state in
            state.ageOverride = ageOverride
            state.sex = sex
        }
        await load()
    }

    /// Days with data in the last `days` days, oldest first (for charts).
    func recentDays(_ days: Int) -> [(record: DayRecord, scores: DayScores?)] {
        let start = today.adding(days: -(days - 1))
        return state.records.filter { $0.date >= start }.map { ($0, snapshot.scores(on: $0.date)) }
    }
}
