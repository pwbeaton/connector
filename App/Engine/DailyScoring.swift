import Foundation

/// The scores and goal results for one day.
nonisolated struct DayScores: Codable, Equatable, Sendable, Identifiable {
    let date: CivilDate
    /// Recovery for this morning (from last night's HRV, resting HR, and sleep).
    let recovery: Recovery
    let sleep: SleepScore?
    /// Effort so far (today) or final (past days); nil when there's no AZM data.
    let effort: Int?
    /// The Effort range recommended for this day.
    let effortTarget: ClosedRange<Int>
    /// Goal results; nil means "no data", which is different from "missed".
    let sleepGoalMet: Bool?
    let stepGoalMet: Bool?
    let effortOnTarget: Bool?

    var id: CivilDate { date }

    /// The three goals in a fixed order, for streaks and tiers.
    var goalResults: [Bool?] { [sleepGoalMet, stepGoalMet, effortOnTarget] }
}

nonisolated enum DailyScoring {
    /// Scores every day in `records`, oldest first. Each day only looks at earlier
    /// days for its baselines and consistency, so history never changes later.
    static func score(_ records: [DayRecord], goals: Goals) -> [DayScores] {
        let sorted = records.sorted { $0.date < $1.date }
        return sorted.map { record in
            score(record, history: sorted, goals: goals)
        }
    }

    static func score(_ record: DayRecord, history: [DayRecord], goals: Goals) -> DayScores {
        let date = record.date

        let recentWakes = history
            .filter { $0.date < date && $0.date >= date.adding(days: -7) }
            .compactMap { $0.sleep?.wakeMinuteOfDay }
        let sleepScore = record.sleep.map {
            SleepScore.score($0, goalMinutes: goals.sleepMinutes, recentWakeMinutes: recentWakes)
        }

        let recovery = RecoveryScore.compute(
            hrv: record.hrvMs,
            hrvBaseline: Baselines.baseline(for: date, in: history) { $0.hrvMs },
            hrvNightsCollected: Baselines.nightsCollected(before: date, in: history) { $0.hrvMs },
            restingHR: record.restingHeartRate,
            restingHRBaseline: Baselines.baseline(for: date, in: history) { $0.restingHeartRate },
            sleepScore: sleepScore?.total
        )
        // Until Recovery is known, aim for the middle of the road.
        let band = recovery.score?.band ?? .steady
        let target = band.effortTarget

        let effort = record.activeZoneMinutes.map { Effort.score(activeZoneMinutes: $0) }
        let effortOnTarget = effort.map { effort in
            // On Recover days, rest is the goal: going over the range doesn't count.
            effort >= target.lowerBound && (band != .recover || effort <= target.upperBound)
        }

        return DayScores(
            date: date,
            recovery: recovery,
            sleep: sleepScore,
            effort: effort,
            effortTarget: target,
            sleepGoalMet: record.sleep.map { $0.minutesAsleep >= goals.sleepMinutes },
            stepGoalMet: record.steps.map { $0 >= goals.steps },
            effortOnTarget: effortOnTarget
        )
    }
}
