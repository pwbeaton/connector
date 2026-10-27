import Foundation

/// One week in numbers, for the shareable recap card. Averages skip days
/// without data (a missing day is never zero).
nonisolated struct WeeklyRecap: Equatable, Sendable {
    let weekStart: CivilDate
    let averageRecovery: Int?
    let averageSleepMinutes: Int?
    let steps: Int
    let activeZoneMinutes: Int
    /// Goals hit (sleep, steps, Effort on target) out of goals with data.
    let goalsHit: Int
    let goalsPossible: Int
    let challengesDone: Int
    let challengesTotal: Int
    let tier: Tier
    let longestStreak: Int

    var weekEnd: CivilDate { weekStart.adding(days: 6) }

    static func make(snapshot: EngineSnapshot, records: [DayRecord], weekStart: CivilDate) -> WeeklyRecap {
        let week = weekStart...weekStart.adding(days: 6)
        let days = snapshot.days.filter { week.contains($0.date) }
        let weekRecords = records.filter { week.contains($0.date) }

        let recoveries = days.compactMap { $0.recovery.score?.total }
        let sleeps = weekRecords.compactMap { $0.sleep?.minutesAsleep }
        let goals = days.flatMap(\.goalResults).compactMap { $0 }

        return WeeklyRecap(
            weekStart: weekStart,
            averageRecovery: average(recoveries),
            averageSleepMinutes: average(sleeps),
            steps: weekRecords.compactMap(\.steps).reduce(0, +),
            activeZoneMinutes: weekRecords.compactMap(\.activeZoneMinutes).reduce(0, +),
            goalsHit: goals.filter { $0 }.count,
            goalsPossible: goals.count,
            challengesDone: snapshot.challenges.filter { $0.weekStart == weekStart && $0.isComplete }.count,
            challengesTotal: snapshot.challenges.filter { $0.weekStart == weekStart }.count,
            tier: snapshot.tier.tier,
            longestStreak: snapshot.streaks.values.map(\.current).max() ?? 0
        )
    }

    private static func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
