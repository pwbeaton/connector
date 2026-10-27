import Foundation

// MARK: - Baselines

/// A personal baseline: the median of the last 30 days (excluding the day being scored).
nonisolated struct Baseline: Equatable, Sendable {
    let median: Double
    let nights: Int
}

nonisolated enum Baselines {
    /// The baseline for `date`, from up to 30 earlier days. Nil until there are
    /// at least 7 nights of data ("Calibrating").
    static func baseline(for date: CivilDate, in records: [DayRecord], value: (DayRecord) -> Double?) -> Baseline? {
        let values = window(before: date, in: records).compactMap(value)
        guard values.count >= ScoreTuning.baselineMinimumNights else { return nil }
        return Baseline(median: median(values), nights: values.count)
    }

    /// Nights of data collected so far toward the baseline (for "Calibrating 4/7").
    static func nightsCollected(before date: CivilDate, in records: [DayRecord], value: (DayRecord) -> Double?) -> Int {
        window(before: date, in: records).compactMap(value).count
    }

    private static func window(before date: CivilDate, in records: [DayRecord]) -> [DayRecord] {
        let start = date.adding(days: -ScoreTuning.baselineWindowDays)
        return records.filter { $0.date >= start && $0.date < date }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

// MARK: - Sleep score

/// The Sleep score and the points behind it (shown as "how is this calculated").
nonisolated struct SleepScore: Codable, Equatable, Sendable {
    let total: Int
    let duration: Double
    let restoration: Double
    let efficiency: Double
    let consistency: Double

    /// - Parameter recentWakeMinutes: local wake times (minutes after midnight) of earlier nights this week.
    static func score(_ sleep: SleepSummary, goalMinutes: Int, recentWakeMinutes: [Int]) -> SleepScore {
        let durationShare = min(1, Double(sleep.minutesAsleep) / Double(max(goalMinutes, 1)))
        let duration = durationShare * ScoreTuning.sleepDurationPoints

        let restorationShare: Double
        if let deep = sleep.deepMinutes, let rem = sleep.remMinutes, sleep.minutesAsleep > 0 {
            let share = Double(deep + rem) / Double(sleep.minutesAsleep)
            restorationShare = min(1, share / ScoreTuning.restorativeShareTarget)
        } else {
            restorationShare = ScoreTuning.restorationWithoutStages
        }
        let restoration = restorationShare * ScoreTuning.sleepRestorationPoints

        let efficiencyRatio = sleep.minutesInBed > 0 ? Double(sleep.minutesAsleep) / Double(sleep.minutesInBed) : 0
        let efficiencyShare = clamp((efficiencyRatio - ScoreTuning.efficiencyFloor)
            / (ScoreTuning.efficiencyCeiling - ScoreTuning.efficiencyFloor))
        let efficiency = efficiencyShare * ScoreTuning.sleepEfficiencyPoints

        let consistencyShare: Double
        if recentWakeMinutes.count >= ScoreTuning.wakeConsistencyMinimumNights {
            let usual = circularMeanMinute(recentWakeMinutes)
            let difference = circularDistance(sleep.wakeMinuteOfDay, usual)
            consistencyShare = clamp(1 - Double(difference) / ScoreTuning.wakeConsistencyToleranceMinutes)
        } else {
            consistencyShare = ScoreTuning.consistencyWithoutHistory
        }
        let consistency = consistencyShare * ScoreTuning.sleepConsistencyPoints

        let total = Int((duration + restoration + efficiency + consistency).rounded())
        return SleepScore(total: min(100, max(0, total)), duration: duration, restoration: restoration,
                          efficiency: efficiency, consistency: consistency)
    }

    /// The average of clock times, treating 23:50 and 00:10 as 20 minutes apart.
    static func circularMeanMinute(_ minutes: [Int]) -> Int {
        let angles = minutes.map { Double($0) / 1440 * 2 * .pi }
        let x = angles.map(cos).reduce(0, +)
        let y = angles.map(sin).reduce(0, +)
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded()) % 1440
    }

    /// Minutes between two clock times, the short way around midnight.
    static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let difference = abs(a - b) % 1440
        return min(difference, 1440 - difference)
    }
}

// MARK: - Recovery

nonisolated enum RecoveryBand: String, Codable, Sendable, CaseIterable {
    case go, steady, recover

    init(score: Int) {
        if score >= ScoreTuning.recoveryGoMinimum {
            self = .go
        } else if score <= ScoreTuning.recoveryRestMaximum {
            self = .recover
        } else {
            self = .steady
        }
    }

    var title: String {
        switch self {
        case .go: "Go"
        case .steady: "Steady"
        case .recover: "Recover"
        }
    }

    /// Today's recommended Effort range for this band.
    var effortTarget: ClosedRange<Int> {
        switch self {
        case .go: ScoreTuning.effortTargetGo
        case .steady: ScoreTuning.effortTargetSteady
        case .recover: ScoreTuning.effortTargetRecover
        }
    }
}

/// The Recovery result for one morning.
nonisolated enum Recovery: Codable, Equatable, Sendable {
    /// Fewer than 7 nights of HRV so far.
    case calibrating(nightsCollected: Int)
    /// No HRV last night (tracker not worn, or not synced yet).
    case unavailable
    case scored(RecoveryScore)

    var score: RecoveryScore? {
        if case .scored(let score) = self { return score }
        return nil
    }
}

nonisolated struct RecoveryScore: Codable, Equatable, Sendable {
    let total: Int
    let band: RecoveryBand
    /// Component scores (0–100); nil when that input was missing.
    let hrvComponent: Double
    let restingHRComponent: Double?
    let sleepComponent: Double?

    static func compute(hrv: Double?, hrvBaseline: Baseline?, hrvNightsCollected: Int,
                        restingHR: Double?, restingHRBaseline: Baseline?, sleepScore: Int?) -> Recovery {
        guard let hrvBaseline, hrvBaseline.median > 0 else {
            return .calibrating(nightsCollected: hrvNightsCollected)
        }
        guard let hrv else { return .unavailable }

        let hrvDeviation = (hrv - hrvBaseline.median) / hrvBaseline.median
        let hrvComponent = clamp(0.5 + 0.5 * hrvDeviation / ScoreTuning.hrvFullScaleDeviation) * 100

        var restingHRComponent: Double?
        if let restingHR, let restingHRBaseline {
            let difference = restingHR - restingHRBaseline.median
            restingHRComponent = clamp(0.5 - 0.5 * difference / ScoreTuning.restingHRFullScaleBPM) * 100
        }
        let sleepComponent = sleepScore.map(Double.init)

        // Missing inputs drop out and the remaining weights are scaled up.
        var weighted = hrvComponent * ScoreTuning.recoveryHRVWeight
        var weights = ScoreTuning.recoveryHRVWeight
        if let restingHRComponent {
            weighted += restingHRComponent * ScoreTuning.recoveryRestingHRWeight
            weights += ScoreTuning.recoveryRestingHRWeight
        }
        if let sleepComponent {
            weighted += sleepComponent * ScoreTuning.recoverySleepWeight
            weights += ScoreTuning.recoverySleepWeight
        }
        let total = Int((weighted / weights).rounded())
        return .scored(RecoveryScore(total: total, band: RecoveryBand(score: total), hrvComponent: hrvComponent,
                                     restingHRComponent: restingHRComponent, sleepComponent: sleepComponent))
    }
}

// MARK: - Effort

nonisolated enum Effort {
    /// 0–100 from Active Zone Minutes. Rises fast at first, then flattens, so 100 is rare.
    static func score(activeZoneMinutes: Int) -> Int {
        let value = 100 * (1 - exp(-Double(max(0, activeZoneMinutes)) / ScoreTuning.effortScaleAZM))
        return min(100, Int(value.rounded()))
    }

    /// Active Zone Minutes needed to reach an Effort score (for "12 more minutes to target").
    static func activeZoneMinutes(forScore score: Int) -> Int {
        let fraction = min(0.99, Double(score) / 100)
        return Int((-ScoreTuning.effortScaleAZM * log(1 - fraction)).rounded(.up))
    }

    nonisolated enum Status: String, Codable, Sendable {
        case below, onTarget, above
    }

    static func status(score: Int, target: ClosedRange<Int>) -> Status {
        if score < target.lowerBound { return .below }
        if score > target.upperBound { return .above }
        return .onTarget
    }
}

/// Clamps to 0...1.
nonisolated func clamp(_ value: Double) -> Double {
    min(1, max(0, value))
}
