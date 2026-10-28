import Foundation

/// The sleep you owe your body: how far recent nights fell short of your sleep goal,
/// over a rolling 14 nights with recent nights counting more. Extra sleep pays it down.
nonisolated struct SleepDebt: Equatable, Sendable {
    nonisolated enum Level: String, Sendable {
        case low, moderate, high

        var title: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            }
        }
    }

    /// One night in the window: minutes slept minus the goal (negative = short).
    nonisolated struct Night: Equatable, Sendable, Identifiable {
        let date: CivilDate
        let balanceMinutes: Int
        var id: CivilDate { date }
    }

    /// Weighted minutes owed (never below zero).
    let minutes: Int
    let goalMinutes: Int
    let nights: [Night]

    /// Under 2 h is low; over 5 h is high (RISE suggests keeping it under 5 h).
    var level: Level {
        if minutes < 120 { return .low }
        if minutes <= 300 { return .moderate }
        return .high
    }

    /// Debt on the morning of `date`, from the nights ending on `date` and the 13 before.
    static func compute(on date: CivilDate, records: [DayRecord], goalMinutes: Int) -> SleepDebt? {
        let window = ScoreTuning.sleepDebtNights
        let start = date.adding(days: -(window - 1))
        let nights = records
            .filter { $0.date >= start && $0.date <= date }
            .compactMap { record in record.sleep.map { Night(date: record.date, balanceMinutes: $0.minutesAsleep - goalMinutes) } }
            .sorted { $0.date < $1.date }
        guard nights.count >= ScoreTuning.sleepDebtMinimumNights else { return nil }

        var owed = 0.0
        for night in nights {
            let age = Double(night.date.days(until: date))
            let weight = 1 - (1 - ScoreTuning.sleepDebtOldestWeight) * age / Double(window - 1)
            owed -= Double(night.balanceMinutes) * weight
        }
        return SleepDebt(minutes: max(0, Int(owed.rounded())), goalMinutes: goalMinutes, nights: nights)
    }
}

/// When to go to bed tonight: your usual wake time, minus your goal, minus a slice of any
/// sleep debt, minus the time you usually lie awake. Keeps the wake time fixed (sleeping in
/// shifts your body clock; going to bed earlier doesn't).
nonisolated struct BedtimePlan: Equatable, Sendable {
    /// Tonight's suggested bedtime, minutes after midnight (at most an hour earlier than usual).
    let bedtime: Int
    /// The bedtime that would fit your goal plus tonight's debt repayment in one go.
    let idealBedtime: Int
    let wakeTime: Int
    /// Extra sleep tonight to pay down debt.
    let extraMinutes: Int
    /// Your usual bedtime over the last week, if known.
    let usualBedtime: Int?

    /// Positive when tonight's bedtime is later than usual, negative when earlier.
    var shiftFromUsual: Int? {
        guard let usualBedtime else { return nil }
        return Self.signedDifference(bedtime, usualBedtime)
    }

    static func make(on date: CivilDate, records: [DayRecord], goalMinutes: Int, debt: SleepDebt?) -> BedtimePlan? {
        let recent = records.filter { $0.date <= date && $0.date > date.adding(days: -7) }.compactMap(\.sleep)
        guard recent.count >= ScoreTuning.wakeConsistencyMinimumNights else { return nil }
        let wake = SleepScore.circularMeanMinute(recent.map(\.wakeMinuteOfDay))
        let usualBed = SleepScore.circularMeanMinute(recent.map(\.bedMinuteOfDay))
        let awake = recent.map { max(0, $0.minutesInBed - $0.minutesAsleep) }.reduce(0, +) / recent.count
        let extra = min(ScoreTuning.sleepDebtMaxExtraMinutes,
                        roundToFive(Double(debt?.minutes ?? 0) / ScoreTuning.sleepDebtRepayNights))
        let ideal = roundToFive(Double((((wake - goalMinutes - extra - awake) % 1440) + 1440) % 1440)) % 1440
        // The body clock shifts about an hour a day at most, so don't ask for more than that at once.
        var bedtime = ideal
        let earlier = signedDifference(ideal, usualBed)
        if earlier < -ScoreTuning.maxBedtimeShiftMinutes {
            bedtime = roundToFive(Double(((usualBed - ScoreTuning.maxBedtimeShiftMinutes) % 1440 + 1440) % 1440)) % 1440
        }
        return BedtimePlan(bedtime: bedtime, idealBedtime: ideal, wakeTime: wake, extraMinutes: extra, usualBedtime: usualBed)
    }

    /// Whether tonight's bedtime was held back from the ideal one.
    var isEasedIn: Bool { bedtime != idealBedtime }

    /// `a − b` in minutes, the short way around midnight.
    static func signedDifference(_ a: Int, _ b: Int) -> Int {
        var difference = (a - b) % 1440
        if difference > 720 { difference -= 1440 }
        if difference < -720 { difference += 1440 }
        return difference
    }

    private static func roundToFive(_ minutes: Double) -> Int {
        Int((minutes / 5).rounded()) * 5
    }
}

nonisolated extension SleepSummary {
    /// Local bedtime as minutes after midnight (the wake-up offset is used for the whole night).
    var bedMinuteOfDay: Int {
        let local = Int(start.timeIntervalSince1970.rounded(.down)) + endUTCOffsetSeconds
        let secondsIntoDay = ((local % 86_400) + 86_400) % 86_400
        return secondsIntoDay / 60
    }
}
