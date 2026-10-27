import Foundation

/// Training tiers, earned by consistency over the last 28 days.
nonisolated enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
    case rookie, bronze, silver, gold, platinum, elite

    var title: String { rawValue.capitalized }

    /// The consistency (percent) needed for this tier.
    var minimumConsistency: Int {
        ScoreTuning.tierThresholds.first { $0.tier == self }?.minimum ?? 0
    }

    var next: Tier? {
        let all = Tier.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    init(consistency: Int) {
        self = ScoreTuning.tierThresholds.first { consistency >= $0.minimum }?.tier ?? .rookie
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

nonisolated struct TierState: Codable, Equatable, Sendable {
    let tier: Tier
    /// Share of goals hit over the window, 0–100.
    let consistency: Int
    let daysInWindow: Int
    /// True until there are 7 days of history (the tier shows "Rookie · calibrating").
    let isCalibrating: Bool

    var pointsToNextTier: Int? {
        tier.next.map { max(0, $0.minimumConsistency - consistency) }
    }
}

nonisolated enum Tiers {
    /// Consistency = goals hit ÷ goals possible over the last 28 complete days
    /// (today isn't over yet). Each day has 3 goals: sleep, steps, Effort on target.
    /// Days without data count as goals missed: consistency means showing up.
    /// The window never reaches back before your first day of data.
    static func compute(scores: [DayScores], today: CivilDate) -> TierState {
        let byDate = Dictionary(scores.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        guard let firstDay = scores.map(\.date).min() else {
            return TierState(tier: .rookie, consistency: 0, daysInWindow: 0, isCalibrating: true)
        }
        let end = today.adding(days: -1)
        let start = max(firstDay, today.adding(days: -ScoreTuning.tierWindowDays))
        let window = start.through(end)
        guard !window.isEmpty else {
            return TierState(tier: .rookie, consistency: 0, daysInWindow: 0, isCalibrating: true)
        }

        let hits = window.reduce(0) { total, date in
            total + (byDate[date]?.goalResults.filter { $0 == true }.count ?? 0)
        }
        let consistency = Int((Double(hits) / Double(window.count * 3) * 100).rounded())
        let isCalibrating = window.count < ScoreTuning.tierMinimumDays
        return TierState(tier: isCalibrating ? .rookie : Tier(consistency: consistency), consistency: consistency,
                         daysInWindow: window.count, isCalibrating: isCalibrating)
    }
}
