import Foundation

/// Personal weekly challenge types. Three are picked each week (rotating), with
/// targets scaled to your own last 4 weeks.
nonisolated enum ChallengeKind: String, Codable, Sendable, CaseIterable {
    case stepsTotal, sleepGoalNights, azmTotal, effortTargetDays, wakeConsistencyDays, stepGoalDays
}

nonisolated struct Challenge: Codable, Equatable, Sendable, Identifiable {
    let kind: ChallengeKind
    let weekStart: CivilDate
    let target: Int
    let progress: Int
    /// For wake consistency: the usual wake time (minutes after midnight).
    let usualWakeMinute: Int?

    var id: String { "\(weekStart)-\(kind.rawValue)" }
    var isComplete: Bool { progress >= target }
    var fraction: Double { target > 0 ? min(1, Double(progress) / Double(target)) : 0 }

    var title: String {
        switch kind {
        case .stepsTotal: "Walk \(target.formatted()) steps"
        case .sleepGoalNights: "Hit your sleep goal on \(target) nights"
        case .azmTotal: "Earn \(target) Active Zone Minutes"
        case .effortTargetDays: "Land your Effort target on \(target) days"
        case .wakeConsistencyDays: "Wake within 30 min of your usual time on \(target) days"
        case .stepGoalDays: "Reach your step goal on \(target) days"
        }
    }
}

/// The group challenge everyone in a group shares, rotating weekly. The server
/// computes the leaderboard with the same rotation (see supabase migration).
nonisolated enum GroupChallengeKind: String, Codable, Sendable, CaseIterable {
    case steps, activeZoneMinutes, longNights, averageSleep

    var title: String {
        switch self {
        case .steps: "Most steps"
        case .activeZoneMinutes: "Most Active Zone Minutes"
        case .longNights: "Most nights of 7+ hours"
        case .averageSleep: "Best average sleep"
        }
    }

    /// The same metric name the server's weekly_leaderboard uses.
    var leaderboardMetric: String {
        switch self {
        case .steps: "steps"
        case .activeZoneMinutes: "azm"
        case .longNights: "long_nights"
        case .averageSleep: "avg_sleep"
        }
    }
}

nonisolated enum Challenges {
    static func group(for weekStart: CivilDate) -> GroupChallengeKind {
        let all = GroupChallengeKind.allCases
        return all[positiveModulo(weekStart.weekIndex, all.count)]
    }

    /// This week's three personal challenges with progress so far.
    static func personal(weekStart: CivilDate, records: [DayRecord], scores: [DayScores], goals: Goals) -> [Challenge] {
        let pool = ChallengeKind.allCases
        let offset = positiveModulo(weekStart.weekIndex, pool.count)
        // Offsets 0, 1, 3 give six different trios over six weeks, each with three distinct kinds.
        let kinds = [0, 1, 3].map { pool[(offset + $0) % pool.count] }

        let historyStart = weekStart.adding(days: -ScoreTuning.challengeHistoryDays)
        let pastRecords = records.filter { $0.date >= historyStart && $0.date < weekStart }
        let pastScores = scores.filter { $0.date >= historyStart && $0.date < weekStart }
        let weekEnd = weekStart.adding(days: 6)
        let weekRecords = records.filter { $0.date >= weekStart && $0.date <= weekEnd }
        let weekScores = scores.filter { $0.date >= weekStart && $0.date <= weekEnd }

        return kinds.map { kind in
            var usualWake: Int?
            let target: Int
            let progress: Int
            switch kind {
            case .stepsTotal:
                let steps = pastRecords.compactMap(\.steps)
                let dailyAverage = steps.isEmpty ? Double(goals.steps) : Double(steps.reduce(0, +)) / Double(steps.count)
                target = roundUp(dailyAverage * 7 * ScoreTuning.challengeStretch, to: 500)
                progress = weekRecords.compactMap(\.steps).reduce(0, +)
            case .azmTotal:
                let azm = pastRecords.compactMap(\.activeZoneMinutes)
                let dailyAverage = azm.isEmpty ? 0 : Double(azm.reduce(0, +)) / Double(azm.count)
                target = max(ScoreTuning.challengeMinimumWeeklyAZM,
                             roundUp(dailyAverage * 7 * ScoreTuning.challengeStretch, to: 10))
                progress = weekRecords.compactMap(\.activeZoneMinutes).reduce(0, +)
            case .sleepGoalNights:
                target = dayTarget(rate: rate(pastScores.map(\.sleepGoalMet)))
                progress = weekScores.filter { $0.sleepGoalMet == true }.count
            case .effortTargetDays:
                target = dayTarget(rate: rate(pastScores.map(\.effortOnTarget)))
                progress = weekScores.filter { $0.effortOnTarget == true }.count
            case .stepGoalDays:
                target = dayTarget(rate: rate(pastScores.map(\.stepGoalMet)))
                progress = weekScores.filter { $0.stepGoalMet == true }.count
            case .wakeConsistencyDays:
                let pastWakes = pastRecords.compactMap { $0.sleep?.wakeMinuteOfDay }
                let usual = pastWakes.isEmpty ? nil : SleepScore.circularMeanMinute(pastWakes)
                usualWake = usual
                target = 5
                progress = usual.map { usual in
                    weekRecords.compactMap { $0.sleep?.wakeMinuteOfDay }
                        .filter { SleepScore.circularDistance($0, usual) <= 30 }.count
                } ?? 0
            }
            return Challenge(kind: kind, weekStart: weekStart, target: target, progress: progress,
                             usualWakeMinute: usualWake)
        }
    }

    /// Your own value for this week's group challenge (the server ranks everyone).
    static func groupValue(_ kind: GroupChallengeKind, weekStart: CivilDate, records: [DayRecord]) -> Double? {
        let week = records.filter { $0.date >= weekStart && $0.date <= weekStart.adding(days: 6) }
        switch kind {
        case .steps:
            let steps = week.compactMap(\.steps)
            return steps.isEmpty ? nil : Double(steps.reduce(0, +))
        case .activeZoneMinutes:
            let azm = week.compactMap(\.activeZoneMinutes)
            return azm.isEmpty ? nil : Double(azm.reduce(0, +))
        case .longNights:
            let nights = week.compactMap(\.sleep)
            return nights.isEmpty ? nil : Double(nights.filter { $0.minutesAsleep >= ScoreTuning.longNightMinutes }.count)
        case .averageSleep:
            let minutes = week.compactMap { $0.sleep?.minutesAsleep }
            return minutes.isEmpty ? nil : Double(minutes.reduce(0, +)) / Double(minutes.count)
        }
    }

    /// Share of known days that met the goal (nil days are ignored).
    private static func rate(_ results: [Bool?]) -> Double? {
        let known = results.compactMap { $0 }
        return known.isEmpty ? nil : Double(known.filter { $0 }.count) / Double(known.count)
    }

    /// One more day than your usual weekly count, between 3 and 7.
    private static func dayTarget(rate: Double?) -> Int {
        guard let rate else { return 4 }
        return min(7, max(3, Int((rate * 7).rounded()) + 1))
    }

    /// Rounds up to a multiple of `step`, ignoring floating-point dust
    /// (10,000 × 7 × 1.1 is 77,000.00000000001, which must stay 77,000).
    private static func roundUp(_ value: Double, to step: Int) -> Int {
        Int((value / Double(step) - 1e-9).rounded(.up)) * step
    }
}

nonisolated func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
    ((value % modulus) + modulus) % modulus
}
