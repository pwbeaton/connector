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

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
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

    /// Reads what's saved on the phone and recomputes every score.
    func load() async {
        state = await services.store.load()
        snapshot = Engine.run(records: state.records, goals: state.goals, today: .today())
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
        lastReport = nil
        await load()
    }

    /// Days with data in the last `days` days, oldest first (for charts).
    func recentDays(_ days: Int) -> [(record: DayRecord, scores: DayScores?)] {
        let start = today.adding(days: -(days - 1))
        return state.records.filter { $0.date >= start }.map { ($0, snapshot.scores(on: $0.date)) }
    }
}
