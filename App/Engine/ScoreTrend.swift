import Foundation

/// The three headline scores, so screens can treat them alike.
nonisolated enum ScoreKind: String, Sendable, CaseIterable, Identifiable {
    case recovery, sleep, effort

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .effort: "Effort"
        }
    }

    /// The score on one day, or nil when there's no data.
    func value(in scores: DayScores?) -> Int? {
        guard let scores else { return nil }
        switch self {
        case .recovery: return scores.recovery.score?.total
        case .sleep: return scores.sleep?.total
        case .effort: return scores.effort
        }
    }
}

/// Day-to-day change and week-over-week direction for a score.
nonisolated enum ScoreTrend {
    nonisolated enum Direction: String, Sendable {
        case up, flat, down
    }

    /// The change from the day before (nil if either day has no score).
    static func dayChange(_ kind: ScoreKind, on date: CivilDate, scores: [DayScores]) -> Int? {
        let byDate = Dictionary(scores.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        guard let today = kind.value(in: byDate[date]),
              let yesterday = kind.value(in: byDate[date.adding(days: -1)]) else { return nil }
        return today - yesterday
    }

    /// The last 7 days' average against the 7 days before, both ending on `date`.
    nonisolated struct WeekComparison: Equatable, Sendable {
        let recentAverage: Double
        let previousAverage: Double
        var change: Double { recentAverage - previousAverage }

        var direction: Direction {
            if change >= 2 { return .up }
            if change <= -2 { return .down }
            return .flat
        }
    }

    static func weekComparison(_ kind: ScoreKind, endingOn date: CivilDate, scores: [DayScores]) -> WeekComparison? {
        func average(from start: CivilDate, to end: CivilDate) -> Double? {
            let values = scores.filter { $0.date >= start && $0.date <= end }.compactMap { kind.value(in: $0) }
            // Need at least 3 days on each side to call a direction.
            guard values.count >= 3 else { return nil }
            return Double(values.reduce(0, +)) / Double(values.count)
        }
        // Today's Effort isn't finished, so it compares completed days only.
        let end = kind == .effort ? date.adding(days: -1) : date
        guard let recent = average(from: end.adding(days: -6), to: end),
              let previous = average(from: end.adding(days: -13), to: end.adding(days: -7)) else { return nil }
        return WeekComparison(recentAverage: recent, previousAverage: previous)
    }

    /// A trailing average over `window` days (with at least half of them scored), for chart lines.
    static func rollingAverage(_ kind: ScoreKind, on date: CivilDate, scores: [DayScores], window: Int = 7) -> Double? {
        let values = scores.filter { $0.date > date.adding(days: -window) && $0.date <= date }.compactMap { kind.value(in: $0) }
        guard values.count * 2 >= window else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
