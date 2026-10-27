import Foundation

/// Everything the screens show, computed in one pass from the day records.
nonisolated struct EngineSnapshot: Codable, Equatable, Sendable {
    let today: CivilDate
    /// Scores for every day with data, oldest first.
    let days: [DayScores]
    let streaks: [StreakKind: StreakState]
    let tier: TierState
    let challenges: [Challenge]
    let groupChallenge: GroupChallengeKind
    let badges: [EarnedBadge]
    let records: [PersonalRecord]
    /// Nights of HRV collected so far toward the baseline (for "Calibrating 4/7").
    let hrvNightsCollected: Int

    func scores(on date: CivilDate) -> DayScores? {
        days.last { $0.date == date }
    }

    var todayScores: DayScores? { scores(on: today) }
}

nonisolated enum Engine {
    static func run(records: [DayRecord], goals: Goals, today: CivilDate) -> EngineSnapshot {
        let records = records.filter { $0.date <= today }.sorted { $0.date < $1.date }
        let scores = DailyScoring.score(records, goals: goals)
        let weekStart = today.weekStart

        return EngineSnapshot(
            today: today,
            days: scores,
            streaks: Dictionary(uniqueKeysWithValues: StreakKind.allCases.map {
                ($0, Streaks.compute($0, scores: scores, today: today))
            }),
            tier: Tiers.compute(scores: scores, today: today),
            challenges: Challenges.personal(weekStart: weekStart, records: records, scores: scores, goals: goals),
            groupChallenge: Challenges.group(for: weekStart),
            badges: Badges.earned(records: records, scores: scores, today: today),
            records: Records.compute(records: records, scores: scores, today: today),
            hrvNightsCollected: Baselines.nightsCollected(before: today.adding(days: 1), in: records) { $0.hrvMs }
        )
    }
}
