import Foundation

/// What a group can see of you. Matches `sharing_settings.category` in the database.
nonisolated enum SharingCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case recovery, sleep, activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .activity: "Activity"
        }
    }

    var detail: String {
        switch self {
        case .recovery: "Recovery score, HRV, resting heart rate"
        case .sleep: "Sleep score and time asleep"
        case .activity: "Effort, steps, Active Zone Minutes, distance"
        }
    }
}

/// The daily summaries uploaded to Supabase. Matches the `daily_metrics.metric` whitelist.
nonisolated enum Metric: String, Codable, Sendable, CaseIterable {
    case recoveryScore = "recovery_score"
    case hrvMs = "hrv_ms"
    case restingHR = "resting_hr"
    case sleepScore = "sleep_score"
    case sleepMinutes = "sleep_minutes"
    case effortScore = "effort_score"
    case azm
    case steps
    case distanceMeters = "distance_m"

    var category: SharingCategory {
        switch self {
        case .recoveryScore, .hrvMs, .restingHR: .recovery
        case .sleepScore, .sleepMinutes: .sleep
        case .effortScore, .azm, .steps, .distanceMeters: .activity
        }
    }
}

/// One row of `daily_metrics` (without user_id, which the backend adds).
nonisolated struct MetricRow: Codable, Equatable, Sendable {
    var date: CivilDate
    var metric: Metric
    var value: Double
    /// Small extras, e.g. sleep stage minutes.
    var detail: [String: Int] = [:]

    /// Identifies the row for "already uploaded?" checks.
    var key: String { "\(date)/\(metric.rawValue)" }

    /// Changes whenever the value or detail changes.
    var fingerprint: String {
        let extras = detail.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return "\(value)|\(extras)"
    }
}

nonisolated enum MetricRows {
    /// The rows for every day with data. Only summaries: no samples, no timestamps.
    static func rows(records: [DayRecord], scores: [DayScores]) -> [MetricRow] {
        let scoresByDate = Dictionary(scores.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return records.flatMap { record -> [MetricRow] in
            let day = scoresByDate[record.date]
            var rows: [MetricRow] = []
            func add(_ metric: Metric, _ value: Double?, detail: [String: Int] = [:]) {
                guard let value, value.isFinite, value >= 0 else { return }
                rows.append(MetricRow(date: record.date, metric: metric, value: value, detail: detail))
            }
            add(.recoveryScore, day?.recovery.score.map { Double($0.total) })
            add(.hrvMs, record.hrvMs.map { ($0 * 10).rounded() / 10 })
            add(.restingHR, record.restingHeartRate.map { ($0 * 10).rounded() / 10 })
            add(.sleepScore, day?.sleep.map { Double($0.total) })
            if let sleep = record.sleep {
                var stages = ["in_bed": sleep.minutesInBed]
                stages["deep"] = sleep.deepMinutes
                stages["rem"] = sleep.remMinutes
                stages["light"] = sleep.lightMinutes
                stages["awake"] = sleep.awakeMinutes
                add(.sleepMinutes, Double(sleep.minutesAsleep), detail: stages)
            }
            add(.effortScore, day?.effort.map(Double.init))
            add(.azm, record.activeZoneMinutes.map(Double.init))
            add(.steps, record.steps.map(Double.init))
            add(.distanceMeters, record.distanceMeters.map { $0.rounded() })
            return rows
        }
    }

    /// The rows Supabase doesn't have yet (new or changed since the last upload).
    static func changed(_ rows: [MetricRow], uploaded: [String: String]) -> [MetricRow] {
        rows.filter { uploaded[$0.key] != $0.fingerprint }
    }
}
