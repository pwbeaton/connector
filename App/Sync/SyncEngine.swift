import Foundation

/// Sends daily summaries to the backend. The real one is Supabase; tests use a fake.
nonisolated protocol MetricUploading: Sendable {
    /// The signed-in account, or nil when signed out (then nothing is uploaded).
    func accountID() async -> String?
    /// Inserts or updates rows (one per user, date, and metric), so re-sending is harmless.
    func upsertMetrics(_ rows: [MetricRow]) async throws
}

/// Receives the widget's numbers after each sync.
nonisolated protocol WidgetUpdating: Sendable {
    func update(_ snapshot: WidgetSnapshot)
}

nonisolated enum SyncStatus: Equatable, Sendable {
    case synced
    /// The Google login expired or was revoked: show "Reconnect Fitbit", never an error screen.
    case reconnectRequired
    /// Offline or an API error. The last synced data stays on screen.
    case failed(String)
}

nonisolated struct SyncReport: Equatable, Sendable {
    var status: SyncStatus
    /// Categories the user didn't grant on Google's consent screen.
    var missing: Set<HealthCategory> = []
    var uploadedRows = 0
    /// Set when health data synced but the upload to friends didn't (it retries next sync).
    var uploadError: String?
}

/// Brings the phone's copy of the user's health data up to date, then uploads the
/// daily summaries that changed. Runs when the app opens, on pull-to-refresh, and
/// in background refresh.
///
/// - The first sync back-fills 90 days, so scores, trends, and tiers work on day one.
/// - Later syncs re-fetch the last 3 days (sleep and HRV arrive late) plus any gap.
/// - Uploads are upserts of changed rows only, so repeating a sync changes nothing.
actor SyncEngine {
    static let backfillDays = 90
    static let refetchDays = 3
    static let uploadBatchSize = 500

    private let source: any HealthDataSource
    private let store: DayStore
    private let uploader: (any MetricUploading)?
    private let widget: (any WidgetUpdating)?
    private let timeZone: @Sendable () -> TimeZone
    private let now: @Sendable () -> Date
    private var running: Task<SyncReport, Never>?

    init(source: any HealthDataSource, store: DayStore, uploader: (any MetricUploading)?,
         widget: (any WidgetUpdating)? = nil, timeZone: @escaping @Sendable () -> TimeZone = { .current },
         now: @escaping @Sendable () -> Date = { .now }) {
        self.source = source
        self.store = store
        self.uploader = uploader
        self.widget = widget
        self.timeZone = timeZone
        self.now = now
    }

    /// Syncs now. If a sync is already running, waits for that one instead of starting another.
    func sync() async -> SyncReport {
        if let running { return await running.value }
        let task = Task { await performSync() }
        running = task
        let report = await task.value
        running = nil
        return report
    }

    /// The dates to fetch: 90 days the first time, then the last 3 days plus any gap.
    static func fetchRange(today: CivilDate, fetchedThrough: CivilDate?) -> ClosedRange<CivilDate> {
        let earliest = today.adding(days: -(backfillDays - 1))
        guard let fetchedThrough else { return earliest...today }
        let start = min(fetchedThrough, today).adding(days: -(refetchDays - 1))
        return max(start, earliest)...today
    }

    private func performSync() async -> SyncReport {
        let now = now()
        let today = CivilDate.today(in: timeZone(), now: now)
        let range = Self.fetchRange(today: today, fetchedThrough: await store.load().fetchedThrough)

        let fetched: HealthFetchResult
        do {
            fetched = try await source.fetch(from: range.lowerBound, through: range.upperBound)
        } catch {
            return SyncReport(status: Self.status(for: error))
        }
        let device = try? await source.device()
        let age = try? await source.profileAge()

        var state: LocalState
        do {
            state = try await store.update { state in
                state.replaceRecords(in: range, with: fetched.records)
                state.fetchedThrough = today
                state.lastSyncAt = now
                state.missingCategories = fetched.missing
                if let device { state.device = device }
                if let age { state.profileAge = age }
            }
        } catch {
            return SyncReport(status: .failed("Couldn't save your data on this iPhone."))
        }

        let engine = Engine.run(records: state.records, goals: state.goals, today: today)
        widget?.update(WidgetSnapshot(engine: engine, todayRecord: state.records.last { $0.date == today },
                                      updatedAt: now))

        var report = SyncReport(status: .synced, missing: fetched.missing)
        guard let uploader, let account = await uploader.accountID() else { return report }
        do {
            if state.accountID != account {
                // A different (or first) account: it has none of these rows yet.
                state = try await store.update { state in
                    state.accountID = account
                    state.uploaded = [:]
                }
            }
            let rows = MetricRows.changed(MetricRows.rows(records: state.records, scores: engine.days),
                                          uploaded: state.uploaded)
            for start in stride(from: 0, to: rows.count, by: Self.uploadBatchSize) {
                let batch = Array(rows[start..<min(start + Self.uploadBatchSize, rows.count)])
                try await uploader.upsertMetrics(batch)
                try await store.update { state in
                    for row in batch { state.uploaded[row.key] = row.fingerprint }
                }
                report.uploadedRows += batch.count
            }
        } catch {
            report.uploadError = "Couldn't share today's numbers with your group. Trying again next sync."
        }
        return report
    }

    static func status(for error: any Error) -> SyncStatus {
        switch error {
        case GoogleAuthError.reconnectRequired, GoogleHealthError.http(status: 401, message: _):
            return .reconnectRequired
        case let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code):
            return .failed("You're offline. Showing your last sync.")
        case GoogleHealthError.accountNotLinked:
            return .failed(GoogleHealthError.accountNotLinkedMessage)
        case GoogleHealthError.http(status: let status, message: _) where status >= 500 || status == 429:
            return .failed("Google Health is busy right now. Try again in a few minutes.")
        default:
            return .failed("Couldn't reach Google Health. Showing your last sync.")
        }
    }
}
