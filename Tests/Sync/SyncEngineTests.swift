import Foundation
import Testing
@testable import App

/// Pretends to be Google Health: serves whatever records are in `cloud`.
nonisolated final class FakeHealthSource: HealthDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var cloud: [CivilDate: DayRecord]
    private var ranges: [ClosedRange<CivilDate>] = []
    private var error: (any Error)?
    private let missing: Set<HealthCategory>

    init(records: [DayRecord], missing: Set<HealthCategory> = []) {
        cloud = Dictionary(records.map { ($0.date, $0) }, uniquingKeysWith: { $1 })
        self.missing = missing
    }

    var fetchedRanges: [ClosedRange<CivilDate>] { lock.withLock { ranges } }
    func set(_ record: DayRecord) { lock.withLock { cloud[record.date] = record } }
    func fail(with error: (any Error)?) { lock.withLock { self.error = error } }

    func fetch(from start: CivilDate, through end: CivilDate) async throws -> HealthFetchResult {
        try lock.withLock {
            if let error { throw error }
            ranges.append(start...end)
            let records = start.through(end).compactMap { cloud[$0] }
            return HealthFetchResult(records: records, missing: missing)
        }
    }

    func device() async throws -> DeviceStatus? {
        DeviceStatus(name: "Fitbit Air", batteryPercent: 80, lastSync: nil)
    }
}

nonisolated final class FakeUploader: MetricUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var account: String?
    private var batches: [[MetricRow]] = []
    private var failing = false

    init(account: String? = "user-1") { self.account = account }

    var uploads: [[MetricRow]] { lock.withLock { batches } }
    var allRows: [MetricRow] { uploads.flatMap { $0 } }
    func signIn(as account: String?) { lock.withLock { self.account = account } }
    func setFailing(_ failing: Bool) { lock.withLock { self.failing = failing } }

    func accountID() async -> String? { lock.withLock { account } }

    func upsertMetrics(_ rows: [MetricRow]) async throws {
        try lock.withLock {
            if failing { throw URLError(.notConnectedToInternet) }
            batches.append(rows)
        }
    }
}

nonisolated final class FakeWidget: WidgetUpdating, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [WidgetSnapshot] = []
    var last: WidgetSnapshot? { lock.withLock { snapshots.last } }
    func update(_ snapshot: WidgetSnapshot) { lock.withLock { snapshots.append(snapshot) } }
}

/// A temporary store file per test.
func temporaryStore() -> DayStore {
    DayStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("daystore-\(UUID().uuidString).json"))
}

/// 9:00 local time on `date` in US Eastern (UTC−4 in October).
func morning(of date: CivilDate) -> Date {
    Date(timeIntervalSince1970: Double(date.dayNumber) * 86_400 + 13 * 3600)
}

struct SyncEngineTests {
    let today = CivilDate(year: 2026, month: 10, day: 27)

    func engine(_ source: FakeHealthSource, store: DayStore, uploader: FakeUploader? = FakeUploader(),
                widget: FakeWidget? = nil, today: CivilDate? = nil) -> SyncEngine {
        let date = morning(of: today ?? self.today)
        let eastern = TimeZone(identifier: "America/New_York")!
        return SyncEngine(source: source, store: store, uploader: uploader, widget: widget,
                          timeZone: { eastern }, now: { date })
    }

    @Test func firstSyncBackfills90Days() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 120))
        let store = temporaryStore()
        let report = await engine(source, store: store).sync()

        #expect(report.status == .synced)
        #expect(source.fetchedRanges == [today.adding(days: -89)...today])
        let state = await store.load()
        #expect(state.records.count == 90)
        #expect(state.records.first?.date == today.adding(days: -89))
        #expect(state.fetchedThrough == today)
        #expect(state.device?.name == "Fitbit Air")
    }

    @Test func laterSyncsRefetchTheLastThreeDays() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 90))
        let store = temporaryStore()
        _ = await engine(source, store: store).sync()
        _ = await engine(source, store: store).sync()
        #expect(source.fetchedRanges.last == today.adding(days: -2)...today)
    }

    @Test func aGapIsFilledFromTheLastSync() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 90))
        let store = temporaryStore()
        _ = await engine(source, store: store, today: today.adding(days: -10)).sync()
        _ = await engine(source, store: store).sync()
        #expect(source.fetchedRanges.last == today.adding(days: -12)...today)
    }

    @Test func lateArrivingSleepReplacesTheDay() async {
        var lastNight = DemoData.records(endingOn: today, days: 1)[0]
        let sleep = lastNight.sleep
        lastNight.sleep = nil
        let source = FakeHealthSource(records: [lastNight])
        let store = temporaryStore()
        _ = await engine(source, store: store).sync()
        #expect(await store.load().records.last?.sleep == nil)

        lastNight.sleep = sleep
        source.set(lastNight)
        _ = await engine(source, store: store).sync()
        #expect(await store.load().records.last?.sleep == sleep)
    }

    @Test func missingDaysStayMissing() async {
        let records = DemoData.records(endingOn: today, days: 10).filter { $0.date != today.adding(days: -3) }
        let store = temporaryStore()
        _ = await engine(FakeHealthSource(records: records), store: store).sync()
        let dates = await store.load().records.map(\.date)
        #expect(!dates.contains(today.adding(days: -3)))
        #expect(dates.count == 9)
    }

    @Test func uploadsEveryRowOnceThenOnlyChanges() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 30))
        let uploader = FakeUploader()
        let store = temporaryStore()

        let first = await engine(source, store: store, uploader: uploader).sync()
        #expect(first.uploadedRows > 200)
        #expect(Set(uploader.allRows.map(\.key)).count == uploader.allRows.count)

        let second = await engine(source, store: store, uploader: uploader).sync()
        #expect(second.uploadedRows == 0, "nothing changed, so nothing is re-sent")

        var todayRecord = DemoData.records(endingOn: today, days: 1)[0]
        todayRecord.steps = 12_345
        source.set(todayRecord)
        let third = await engine(source, store: store, uploader: uploader).sync()
        #expect(third.uploadedRows >= 1)
        #expect(uploader.uploads.last?.contains { $0.metric == .steps && $0.value == 12_345 } == true)
    }

    @Test func largeUploadsAreBatched() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 90))
        let uploader = FakeUploader()
        let report = await engine(source, store: temporaryStore(), uploader: uploader).sync()
        #expect(uploader.uploads.count > 1)
        #expect(uploader.uploads.allSatisfy { $0.count <= SyncEngine.uploadBatchSize })
        #expect(report.uploadedRows == uploader.allRows.count)
    }

    @Test func nothingIsUploadedWhenSignedOut() async {
        let uploader = FakeUploader(account: nil)
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 10))
        let report = await engine(source, store: temporaryStore(), uploader: uploader).sync()
        #expect(report.status == .synced)
        #expect(uploader.uploads.isEmpty)
    }

    @Test func aDifferentAccountGetsEverything() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 10))
        let uploader = FakeUploader(account: "user-1")
        let store = temporaryStore()
        let first = await engine(source, store: store, uploader: uploader).sync()
        uploader.signIn(as: "user-2")
        let second = await engine(source, store: store, uploader: uploader).sync()
        #expect(second.uploadedRows == first.uploadedRows)
    }

    @Test func aFailedUploadIsRetriedNextSync() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 10))
        let uploader = FakeUploader()
        uploader.setFailing(true)
        let store = temporaryStore()
        let failed = await engine(source, store: store, uploader: uploader).sync()
        #expect(failed.status == .synced, "health data still synced")
        #expect(failed.uploadError != nil)

        uploader.setFailing(false)
        let retried = await engine(source, store: store, uploader: uploader).sync()
        #expect(retried.uploadError == nil)
        #expect(retried.uploadedRows > 0)
    }

    @Test func anExpiredGoogleLoginAsksToReconnect() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 10))
        let store = temporaryStore()
        _ = await engine(source, store: store).sync()
        source.fail(with: GoogleAuthError.reconnectRequired)
        let report = await engine(source, store: store).sync()
        #expect(report.status == .reconnectRequired)
        #expect(await store.load().records.count == 10, "the last synced data is kept")
    }

    @Test func offlineKeepsTheLastSync() async {
        let source = FakeHealthSource(records: [])
        source.fail(with: URLError(.notConnectedToInternet))
        let report = await engine(source, store: temporaryStore()).sync()
        #expect(report.status == .failed("You're offline. Showing your last sync."))
    }

    @Test func reportsCategoriesTheUserDidNotGrant() async {
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 5), missing: [.heart])
        let store = temporaryStore()
        let report = await engine(source, store: store).sync()
        #expect(report.missing == [.heart])
        #expect(await store.load().missingCategories == [.heart])
    }

    @Test func updatesTheWidget() async throws {
        let widget = FakeWidget()
        let source = FakeHealthSource(records: DemoData.records(endingOn: today, days: 30))
        _ = await engine(source, store: temporaryStore(), widget: widget).sync()
        let snapshot = try #require(widget.last)
        #expect(snapshot.date == "2026-10-27")
        #expect(snapshot.recovery != nil)
        #expect(snapshot.steps != nil)
    }

    @Test(arguments: [
        (nil as Int?, -89),  // first sync: 90 days
        (0, -2),             // synced today: re-fetch 3 days
        (-1, -3),            // synced yesterday
        (-200, -89),         // a long gap is capped at 90 days
        (2, -2),             // flew west past midnight: still ends today
    ])
    func fetchRange(lastSyncOffset: Int?, expectedStart: Int) {
        let range = SyncEngine.fetchRange(today: today, fetchedThrough: lastSyncOffset.map { today.adding(days: $0) })
        #expect(range == today.adding(days: expectedStart)...today)
    }
}

struct DayStoreTests {
    @Test func savesAndReloads() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daystore-\(UUID().uuidString).json")
        let records = DemoData.records(endingOn: CivilDate(year: 2026, month: 10, day: 27), days: 3)
        try await DayStore(fileURL: url).update { state in
            state.records = records
            state.goals.steps = 10_000
            state.uploaded["2026-10-27/steps"] = "1"
        }
        let reloaded = await DayStore(fileURL: url).load()
        #expect(reloaded.records == records)
        #expect(reloaded.goals.steps == 10_000)
        #expect(reloaded.uploaded.count == 1)
    }

    @Test func aMissingFileIsAnEmptyState() async {
        #expect(await temporaryStore().load() == LocalState())
    }

    @Test func resetForgetsEverything() async throws {
        let store = temporaryStore()
        try await store.update { $0.accountID = "user-1" }
        try await store.reset()
        #expect(await store.load().accountID == nil)
    }

    @Test func replacingARangeKeepsOtherDays() {
        let today = CivilDate(year: 2026, month: 10, day: 27)
        var state = LocalState(records: DemoData.records(endingOn: today, days: 5))
        state.replaceRecords(in: today.adding(days: -1)...today, with: [DayRecord(date: today, steps: 5)])
        #expect(state.records.map(\.date) == [-4, -3, -2, 0].map { today.adding(days: $0) })
        #expect(state.records.last?.steps == 5)
    }
}
