import Foundation
import Testing
@testable import App

struct MetricRowsTests {
    let today = CivilDate(year: 2026, month: 10, day: 27)

    @Test func metricNamesMatchTheDatabaseWhitelist() {
        // supabase/migrations: daily_metrics.metric check constraint.
        #expect(Set(Metric.allCases.map(\.rawValue)) == [
            "recovery_score", "hrv_ms", "resting_hr", "sleep_score", "sleep_minutes",
            "effort_score", "azm", "steps", "distance_m",
        ])
    }

    @Test func categoriesMatchTheDatabase() {
        // supabase/migrations: private.metric_category().
        #expect(Metric.allCases.filter { $0.category == .recovery } == [.recoveryScore, .hrvMs, .restingHR])
        #expect(Metric.allCases.filter { $0.category == .sleep } == [.sleepScore, .sleepMinutes])
        #expect(Set(SharingCategory.allCases.map(\.rawValue)) == ["recovery", "sleep", "activity"])
    }

    @Test func aFullDayHasNineRows() {
        let records = DemoData.records(endingOn: today, days: 30)
        let scores = DailyScoring.score(records, goals: Goals())
        let rows = MetricRows.rows(records: records, scores: scores).filter { $0.date == today }
        #expect(Set(rows.map(\.metric)) == Set(Metric.allCases))
        let sleep = rows.first { $0.metric == .sleepMinutes }
        #expect(sleep?.detail["deep"] != nil)
        #expect(sleep?.detail["in_bed"] != nil)
    }

    @Test func missingValuesAreNeverSentAsZero() {
        let record = DayRecord(date: today, steps: 4000)
        let rows = MetricRows.rows(records: [record], scores: DailyScoring.score([record], goals: Goals()))
        #expect(rows.map(\.metric) == [.steps])
    }

    @Test func onlyNewOrChangedRowsAreSent() {
        let rows = [MetricRow(date: today, metric: .steps, value: 5000),
                    MetricRow(date: today, metric: .azm, value: 20)]
        let uploaded = [rows[0].key: rows[0].fingerprint, rows[1].key: "old"]
        #expect(MetricRows.changed(rows, uploaded: uploaded) == [rows[1]])
    }

    @Test func detailChangesTheFingerprint() {
        let plain = MetricRow(date: today, metric: .sleepMinutes, value: 400)
        var staged = plain
        staged.detail = ["deep": 60]
        #expect(plain.fingerprint != staged.fingerprint)
    }
}

struct DeviceStatusTests {
    func device(_ version: String?, type: String? = "TRACKER", battery: Int? = nil) -> PairedDeviceDTO {
        PairedDeviceDTO(name: "users/me/pairedDevices/1", deviceVersion: version, deviceType: type,
                        batteryLevel: battery, batteryStatus: nil, lastSyncTime: "2026-10-27T12:58:00Z")
    }

    @Test func prefersTheFitbitAir() {
        let status = DeviceStatus(devices: [device("Charge 6"), device("Fitbit Air", battery: 80)])
        #expect(status?.name == "Fitbit Air")
        #expect(status?.batteryPercent == 80)
        #expect(status?.lastSync == Date(timeIntervalSince1970: 1_793_105_880))
    }

    @Test func ignoresScales() {
        #expect(DeviceStatus(devices: [device("Aria", type: "SCALE")]) == nil)
        #expect(DeviceStatus(devices: []) == nil)
    }
}

struct WidgetSnapshotTests {
    let today = CivilDate(year: 2026, month: 10, day: 27)

    @Test func carriesTodaysNumbers() {
        let records = DemoData.records(endingOn: today, days: 30)
        let engine = Engine.run(records: records, goals: Goals(), today: today)
        let snapshot = WidgetSnapshot(engine: engine, todayRecord: records.last, updatedAt: .distantPast)
        #expect(snapshot.date == "2026-10-27")
        #expect(snapshot.recovery == engine.todayScores?.recovery.score?.total)
        #expect(snapshot.sleep == engine.todayScores?.sleep?.total)
        #expect(snapshot.steps == records.last?.steps)
        #expect(snapshot.calibratingNights == nil)
    }

    @Test func showsCalibrationBeforeSevenNights() {
        let records = DemoData.records(endingOn: today, days: 4)
        let engine = Engine.run(records: records, goals: Goals(), today: today)
        let snapshot = WidgetSnapshot(engine: engine, todayRecord: records.last, updatedAt: .distantPast)
        #expect(snapshot.recovery == nil)
        #expect(snapshot.calibratingNights == 3)
    }

    @Test func roundTripsThroughTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        try WidgetSnapshotFile.save(.sample, to: url)
        #expect(WidgetSnapshotFile.load(from: url) == .sample)
    }
}
