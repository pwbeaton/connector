import Foundation

// MARK: - Biological age
//
// An "effective age" estimate, the same idea as WHOOP Age, heart age, and lung age:
// each metric's published all-cause mortality hazard ratio (HR) is turned into years
// with the Gompertz law. Mortality rises about 10% per year of adult age, so a hazard
// ratio is worth  t = ln(HR) / ln(1.10) ≈ 10.5 × ln(HR)  years. The metric adds years
// when it's worse than a healthy reference and takes them away when it's better.
// Biological age = your age + the sum of those years. docs/SCORES.md lists every
// number and its source.

nonisolated enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case female, male

    var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

/// One metric's push on biological age.
nonisolated struct AgeContributor: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        case vo2Max, restingHeartRate, steps, activeZoneMinutes, sleepDuration, sleepConsistency

        var title: String {
            switch self {
            case .vo2Max: "Cardio fitness (VO₂ max)"
            case .restingHeartRate: "Resting heart rate"
            case .steps: "Daily steps"
            case .activeZoneMinutes: "Active Zone Minutes"
            case .sleepDuration: "Sleep duration"
            case .sleepConsistency: "Sleep consistency"
            }
        }

        var symbol: String {
            switch self {
            case .vo2Max: "lungs.fill"
            case .restingHeartRate: "heart.fill"
            case .steps: "figure.walk"
            case .activeZoneMinutes: "bolt.heart.fill"
            case .sleepDuration: "bed.double.fill"
            case .sleepConsistency: "alarm.fill"
            }
        }
    }

    let kind: Kind
    /// Years added (positive) or taken away (negative). Nil when there isn't enough data.
    let years: Double?
    /// Your value, e.g. "46 ml/kg/min" or "8,420 a day".
    let value: String
    /// The healthy reference, e.g. "target 42+" .
    let reference: String

    var id: Kind { kind }
}

/// Biological age as of one day.
nonisolated struct BiologicalAgeResult: Codable, Equatable, Sendable {
    let date: CivilDate
    let chronologicalAge: Int
    let biologicalAge: Double
    let contributors: [AgeContributor]

    /// Negative when you're "younger" than your age.
    var difference: Double { biologicalAge - Double(chronologicalAge) }
}

/// How biological age moved over the last few weeks.
nonisolated struct BiologicalAgeTrend: Equatable, Sendable {
    nonisolated enum Direction: String, Sendable {
        case improving, steady, worsening

        var title: String {
            switch self {
            case .improving: "Improving"
            case .steady: "Steady"
            case .worsening: "Getting older"
            }
        }
    }

    /// Change in years (negative = younger) since `since`.
    let change: Double
    let since: CivilDate
    let direction: Direction
}

nonisolated enum BiologicalAge {
    // MARK: Tuning (sources in docs/SCORES.md)

    /// Years per unit of ln(hazard ratio): 1 / ln(1.10), from the Gompertz law.
    static let yearsPerLogHazard = 1 / log(1.10)
    /// Days of history behind each estimate.
    static let windowDays = 60
    /// Days with data needed in the window before an estimate is shown.
    static let minimumDays = 14
    /// Trend: compare with the estimate this many days earlier.
    static let trendDays = 28
    /// Changes smaller than this (years) count as steady.
    static let steadyBand = 0.2
    /// VO₂ max and resting HR both measure cardio fitness; steps and Active Zone Minutes
    /// both measure activity. Each member of a pair counts at this share so the overlap
    /// isn't counted twice (WHOOP corrects for the same overlap).
    static let overlapShare = 0.75

    /// VO₂ max per +1 MET (3.5 ml/kg/min): HR 0.87 (Kodama et al., JAMA 2009).
    static let vo2HazardPerMET = 0.87
    /// Resting HR per +10 bpm: HR 1.09 (Zhang et al., CMAJ 2016).
    static let restingHRHazardPer10 = 1.09
    /// Short sleep: HR 1.12 (Cappuccio et al., Sleep 2010), applied per hour under 7 h, up to 2 h.
    static let shortSleepHazardPerHour = 1.12

    /// Minimum healthy VO₂ max by age (WHOOP Healthspan white paper, figure 4), ages 20…100 every 5 years.
    static let vo2TargetsFemale: [Double] = [40, 40, 38, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21, 20, 19, 18]
    static let vo2TargetsMale: [Double] = [46, 46, 44, 42, 40, 37, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21]

    // MARK: Timeline

    /// An estimate for every day from the first one with enough data through `today`.
    static func timeline(records: [DayRecord], age: Int?, sex: BiologicalSex?, today: CivilDate) -> [CivilDate: BiologicalAgeResult] {
        guard let age, age >= 18 else { return [:] }
        let sorted = records.filter { $0.date <= today }.sorted { $0.date < $1.date }
        guard let first = sorted.first?.date else { return [:] }
        var result: [CivilDate: BiologicalAgeResult] = [:]
        for date in first.through(today) {
            if let estimate = estimate(on: date, records: sorted, age: age, sex: sex) {
                result[date] = estimate
            }
        }
        return result
    }

    /// The trend on `date`: today's estimate against the one `trendDays` earlier
    /// (or the earliest one at least 7 days earlier).
    static func trend(on date: CivilDate, in timeline: [CivilDate: BiologicalAgeResult]) -> BiologicalAgeTrend? {
        guard let now = timeline[date] else { return nil }
        let earlier = timeline.values
            .filter { $0.date <= date.adding(days: -7) && $0.date >= date.adding(days: -trendDays) }
            .min { $0.date < $1.date }
        guard let earlier else { return nil }
        let change = now.biologicalAge - earlier.biologicalAge
        let direction: BiologicalAgeTrend.Direction = change <= -steadyBand ? .improving
            : (change >= steadyBand ? .worsening : .steady)
        return BiologicalAgeTrend(change: change, since: earlier.date, direction: direction)
    }

    // MARK: One estimate

    /// Biological age on `date` from the `windowDays` before it. Nil until there's enough data.
    static func estimate(on date: CivilDate, records: [DayRecord], age: Int, sex: BiologicalSex?) -> BiologicalAgeResult? {
        let start = date.adding(days: -(windowDays - 1))
        let window = records.filter { $0.date >= start && $0.date <= date && !$0.isEmpty }
        guard window.count >= minimumDays else { return nil }
        // The day itself may be unfinished (today), so activity uses completed days only.
        let completed = window.filter { $0.date < date }

        let contributors: [AgeContributor] = [
            vo2Max(window.compactMap(\.vo2Max), age: age, sex: sex),
            restingHeartRate(window.compactMap(\.restingHeartRate), sex: sex),
            steps(completed.compactMap(\.steps), age: age),
            activeZoneMinutes(completed.compactMap(\.activeZoneMinutes)),
            sleepDuration(window.compactMap { $0.sleep?.minutesAsleep }),
            sleepConsistency(window.compactMap { $0.sleep?.wakeMinuteOfDay }),
        ]
        let total = contributors.compactMap(\.years).reduce(0, +)
        return BiologicalAgeResult(date: date, chronologicalAge: age,
                                   biologicalAge: Double(age) + total, contributors: contributors)
    }

    // MARK: Contributors

    static func vo2Target(age: Int, sex: BiologicalSex?) -> Double {
        let position = min(16, max(0, Double(age - 20) / 5))
        let low = Int(position.rounded(.down)), high = min(16, low + 1)
        func at(_ table: [Double]) -> Double {
            table[low] + (table[high] - table[low]) * (position - Double(low))
        }
        switch sex {
        case .female: return at(vo2TargetsFemale)
        case .male: return at(vo2TargetsMale)
        case nil: return (at(vo2TargetsFemale) + at(vo2TargetsMale)) / 2
        }
    }

    static func vo2Max(_ values: [Double], age: Int, sex: BiologicalSex?) -> AgeContributor {
        let target = vo2Target(age: age, sex: sex)
        let reference = "target \(Int(target.rounded()))+"
        guard values.count >= 3 else {
            return AgeContributor(kind: .vo2Max, years: nil, value: "Not enough data", reference: reference)
        }
        let value = Baselines.median(values)
        let mets = (value - target) / 3.5
        let years = clamp(yearsPerLogHazard * log(vo2HazardPerMET) * mets, -5, 8) * overlapShare
        return AgeContributor(kind: .vo2Max, years: years, value: "\(Int(value.rounded())) ml/kg/min", reference: reference)
    }

    static func restingHRReference(sex: BiologicalSex?) -> Double {
        switch sex {
        case .female: 64
        case .male: 60
        case nil: 62
        }
    }

    static func restingHeartRate(_ values: [Double], sex: BiologicalSex?) -> AgeContributor {
        let ref = restingHRReference(sex: sex)
        let reference = "neutral at \(Int(ref)) bpm"
        guard values.count >= 7 else {
            return AgeContributor(kind: .restingHeartRate, years: nil, value: "Not enough data", reference: reference)
        }
        let value = Baselines.median(values)
        let years = clamp(yearsPerLogHazard * log(restingHRHazardPer10) * (value - ref) / 10, -2, 4) * overlapShare
        return AgeContributor(kind: .restingHeartRate, years: years, value: "\(Int(value.rounded())) bpm", reference: reference)
    }

    /// Paluch et al., Lancet Public Health 2022: hazard ratios by daily-step quartile
    /// (medians 3,553 · 5,801 · 7,842 · 10,901 steps → HR 1 · 0.60 · 0.55 · 0.47).
    /// Neutral at 8,000 steps; benefits level off sooner after 60, so older users get credit sooner.
    static let stepCurve: [(steps: Double, hazard: Double)] = [(3_553, 1), (5_801, 0.60), (7_842, 0.55), (10_901, 0.47)]

    static func steps(_ values: [Int], age: Int) -> AgeContributor {
        let neutral = age >= 60 ? 6_000.0 : 8_000.0
        let reference = "neutral at \(Format.count(Int(neutral)))"
        guard values.count >= 7 else {
            return AgeContributor(kind: .steps, years: nil, value: "Not enough data", reference: reference)
        }
        let average = Double(values.reduce(0, +)) / Double(values.count)
        // Older adults reach the same benefit with fewer steps, so scale them onto the 8,000 curve.
        let scaled = average * 8_000 / neutral
        let hazard = interpolate(scaled, stepCurve.map { ($0.steps, $0.hazard) })
        let neutralHazard = interpolate(8_000, stepCurve.map { ($0.steps, $0.hazard) })
        let years = clamp(yearsPerLogHazard * log(hazard / neutralHazard), -1.5, 4) * overlapShare
        return AgeContributor(kind: .steps, years: years, value: "\(Format.count(Int(average.rounded()))) a day",
                              reference: reference)
    }

    /// Arem et al., JAMA Internal Medicine 2015 (661,137 adults): HR 1 with no exercise,
    /// 0.80 below the 150-minute guideline, 0.69 at 1–2×, 0.63 at 2–3×, 0.61 at 3–5×.
    /// Fitbit's Active Zone Minutes count vigorous minutes double, like the guideline.
    static let weeklyActivityCurve: [(minutes: Double, hazard: Double)] = [(0, 1), (75, 0.80), (150, 0.69), (300, 0.63), (450, 0.61)]

    static func activeZoneMinutes(_ values: [Int]) -> AgeContributor {
        let reference = "neutral at 150 a week"
        guard values.count >= 7 else {
            return AgeContributor(kind: .activeZoneMinutes, years: nil, value: "Not enough data", reference: reference)
        }
        let weekly = Double(values.reduce(0, +)) / Double(values.count) * 7
        let curve = weeklyActivityCurve.map { ($0.minutes, $0.hazard) }
        let years = clamp(yearsPerLogHazard * log(interpolate(weekly, curve) / interpolate(150, curve)), -1.5, 4) * overlapShare
        return AgeContributor(kind: .activeZoneMinutes, years: years, value: "\(Int(weekly.rounded())) a week",
                              reference: reference)
    }

    static func sleepDuration(_ minutes: [Int]) -> AgeContributor {
        let reference = "7–9 h"
        guard minutes.count >= 7 else {
            return AgeContributor(kind: .sleepDuration, years: nil, value: "Not enough data", reference: reference)
        }
        let average = Double(minutes.reduce(0, +)) / Double(minutes.count)
        let hours = average / 60
        let years: Double
        if hours < 7 {
            years = yearsPerLogHazard * log(shortSleepHazardPerHour) * min(2, 7 - hours)
        } else if hours <= 9 {
            // A small credit for 7–9 hours, as in the WHOOP model; longer sleep earns nothing.
            years = -0.3
        } else {
            years = 0
        }
        return AgeContributor(kind: .sleepDuration, years: years, value: Format.duration(minutes: Int(average.rounded())),
                              reference: reference)
    }

    /// Windred et al., Sleep 2024 (60,977 adults): the most regular sleepers had HR 0.70 against
    /// the least regular. Mapped onto how much your wake time varies: ±20 min → −1.3 years,
    /// ±60 min → neutral, ±2 h → +2.2 years.
    static func sleepConsistency(_ wakeMinutes: [Int]) -> AgeContributor {
        let reference = "within ±60 min"
        guard wakeMinutes.count >= 7 else {
            return AgeContributor(kind: .sleepConsistency, years: nil, value: "Not enough data", reference: reference)
        }
        let spread = circularStandardDeviation(wakeMinutes)
        let years = interpolate(spread, [(20, -1.3), (60, 0), (120, 2.2)])
        return AgeContributor(kind: .sleepConsistency, years: years, value: "wake time ±\(Int(spread.rounded())) min",
                              reference: reference)
    }

    // MARK: Math helpers

    /// Standard deviation of clock times in minutes, treating 23:50 and 00:10 as 20 minutes apart.
    static func circularStandardDeviation(_ minutes: [Int]) -> Double {
        guard minutes.count > 1 else { return 0 }
        let mean = SleepScore.circularMeanMinute(minutes)
        let squares = minutes.map { pow(Double(SleepScore.circularDistance($0, mean)), 2) }
        return sqrt(squares.reduce(0, +) / Double(minutes.count))
    }

    /// Straight-line interpolation through `points` (sorted by x), flat beyond both ends.
    static func interpolate(_ x: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.0 {
            return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}
