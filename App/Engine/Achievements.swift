import Foundation

// MARK: - Badges

nonisolated struct BadgeDefinition: Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String
    /// SF Symbol name.
    let symbol: String
}

nonisolated struct EarnedBadge: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let earnedOn: CivilDate

    var definition: BadgeDefinition? { Badges.all.first { $0.id == id } }
}

nonisolated enum Badges {
    static let all: [BadgeDefinition] = [
        BadgeDefinition(id: "day-one", title: "Day One", detail: "Synced your first day", symbol: "flag.fill"),
        BadgeDefinition(id: "calibrated", title: "Calibrated", detail: "7 nights of HRV: Recovery unlocked", symbol: "dial.medium.fill"),
        BadgeDefinition(id: "first-10k", title: "First 10K", detail: "10,000 steps in a day", symbol: "figure.walk"),
        BadgeDefinition(id: "20k-club", title: "20K Club", detail: "20,000 steps in a day", symbol: "figure.walk.motion"),
        BadgeDefinition(id: "10k-week", title: "10K Week", detail: "10,000+ steps 7 days in a row", symbol: "calendar.badge.checkmark"),
        BadgeDefinition(id: "marathon-day", title: "Marathon Day", detail: "26.2 miles in a day", symbol: "medal.fill"),
        BadgeDefinition(id: "100-mile-month", title: "100-Mile Month", detail: "100 miles in 30 days", symbol: "map.fill"),
        BadgeDefinition(id: "heart-healthy-week", title: "Heart Healthy", detail: "150 Active Zone Minutes in a week", symbol: "heart.fill"),
        BadgeDefinition(id: "zone-master", title: "Zone Master", detail: "300 Active Zone Minutes in a week", symbol: "bolt.heart.fill"),
        BadgeDefinition(id: "full-tank", title: "Full Tank", detail: "8 hours asleep in one night", symbol: "bed.double.fill"),
        BadgeDefinition(id: "iron-week", title: "Iron Week", detail: "Sleep goal every night for a week", symbol: "moon.stars.fill"),
        BadgeDefinition(id: "in-the-green", title: "In the Green", detail: "Go recovery 3 days in a row", symbol: "arrow.up.heart.fill"),
        BadgeDefinition(id: "bounce-back", title: "Bounce Back", detail: "From Recover to Go overnight", symbol: "arrow.uturn.up"),
        BadgeDefinition(id: "dialed-in", title: "Dialed In", detail: "Effort on target 5 days in a week", symbol: "scope"),
        BadgeDefinition(id: "on-a-roll", title: "On a Roll", detail: "A 7-day streak", symbol: "flame.fill"),
        BadgeDefinition(id: "unbreakable", title: "Unbreakable", detail: "A 30-day streak", symbol: "flame.circle.fill"),
        BadgeDefinition(id: "silver-tier", title: "Silver Tier", detail: "Reached Silver consistency", symbol: "shield.lefthalf.filled"),
        BadgeDefinition(id: "gold-tier", title: "Gold Tier", detail: "Reached Gold consistency", symbol: "shield.fill"),
        BadgeDefinition(id: "platinum-tier", title: "Platinum Tier", detail: "Reached Platinum consistency", symbol: "shield.checkered"),
        BadgeDefinition(id: "elite-tier", title: "Elite Tier", detail: "Reached Elite consistency", symbol: "crown.fill"),
    ]

    /// Every badge earned so far, with the first day it was earned.
    static func earned(records: [DayRecord], scores: [DayScores], today: CivilDate) -> [EarnedBadge] {
        let records = records.sorted { $0.date < $1.date }.filter { $0.date <= today }
        let scores = scores.sorted { $0.date < $1.date }.filter { $0.date <= today }
        var earned: [String: CivilDate] = [:]
        func award(_ id: String, _ date: CivilDate) {
            if earned[id] == nil || date < earned[id]! { earned[id] = date }
        }

        // Single-day achievements.
        for record in records where !record.isEmpty {
            award("day-one", record.date)
            if let steps = record.steps {
                if steps >= 10_000 { award("first-10k", record.date) }
                if steps >= 20_000 { award("20k-club", record.date) }
            }
            if let meters = record.distanceMeters, meters >= 42_195 { award("marathon-day", record.date) }
            if let asleep = record.sleep?.minutesAsleep, asleep >= 480 { award("full-tank", record.date) }
        }

        // Rolling windows over consecutive days.
        let byDate = Dictionary(records.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        for record in records {
            let last7 = (0..<7).map { record.date.adding(days: -$0) }
            if last7.allSatisfy({ (byDate[$0]?.steps ?? 0) >= 10_000 }) { award("10k-week", record.date) }
            let last30 = (0..<30).compactMap { byDate[record.date.adding(days: -$0)]?.distanceMeters }
            if last30.reduce(0, +) >= 160_934 { award("100-mile-month", record.date) }
        }

        // Calendar weeks (Monday to Sunday).
        let weeks = Dictionary(grouping: records, by: { $0.date.weekStart })
        let scoreWeeks = Dictionary(grouping: scores, by: { $0.date.weekStart })
        for (weekStart, days) in weeks {
            let lastDay = days.map(\.date).max() ?? weekStart
            let azm = days.compactMap(\.activeZoneMinutes).reduce(0, +)
            if azm >= 150 { award("heart-healthy-week", lastDay) }
            if azm >= 300 { award("zone-master", lastDay) }
        }
        for (_, days) in scoreWeeks {
            let lastDay = days.map(\.date).max()!
            if days.filter({ $0.sleepGoalMet == true }).count == 7 { award("iron-week", lastDay) }
            if days.filter({ $0.effortOnTarget == true }).count >= 5 { award("dialed-in", lastDay) }
        }

        // Recovery patterns.
        var previousBand: RecoveryBand?
        var goRun = 0
        var nightsCalibrated = false
        for day in scores {
            guard let score = day.recovery.score else {
                previousBand = nil
                goRun = 0
                continue
            }
            if !nightsCalibrated {
                award("calibrated", day.date)
                nightsCalibrated = true
            }
            goRun = score.band == .go ? goRun + 1 : 0
            if goRun >= 3 { award("in-the-green", day.date) }
            if previousBand == .recover && score.band == .go { award("bounce-back", day.date) }
            previousBand = score.band
        }

        // Streak milestones (any of the three streaks).
        for kind in StreakKind.allCases {
            for entry in Streaks.history(kind, scores: scores, today: today) {
                if entry.state.current >= 7 { award("on-a-roll", entry.date) }
                if entry.state.current >= 30 { award("unbreakable", entry.date) }
            }
        }

        // Tier milestones: the tier as it stood at the start of each day.
        for day in scores {
            let tier = Tiers.compute(scores: scores.filter { $0.date < day.date }, today: day.date).tier
            if tier >= .silver { award("silver-tier", day.date) }
            if tier >= .gold { award("gold-tier", day.date) }
            if tier >= .platinum { award("platinum-tier", day.date) }
            if tier >= .elite { award("elite-tier", day.date) }
        }

        return earned
            .map { EarnedBadge(id: $0.key, earnedOn: $0.value) }
            .sorted { ($0.earnedOn, $0.id) < ($1.earnedOn, $1.id) }
    }
}

// MARK: - Personal records

nonisolated enum RecordKind: String, Codable, Sendable, CaseIterable {
    case mostSteps, mostAZM, longestSleep, highestHRV, lowestRestingHR, bestRecovery, longestStreak

    var title: String {
        switch self {
        case .mostSteps: "Most steps"
        case .mostAZM: "Most Active Zone Minutes"
        case .longestSleep: "Longest sleep"
        case .highestHRV: "Highest HRV"
        case .lowestRestingHR: "Lowest resting HR"
        case .bestRecovery: "Best Recovery"
        case .longestStreak: "Longest streak"
        }
    }
}

nonisolated struct PersonalRecord: Codable, Equatable, Sendable, Identifiable {
    let kind: RecordKind
    let value: Double
    let date: CivilDate

    var id: RecordKind { kind }
}

nonisolated enum Records {
    static func compute(records: [DayRecord], scores: [DayScores], today: CivilDate) -> [PersonalRecord] {
        var result: [PersonalRecord] = []
        func best(_ kind: RecordKind, _ values: [(CivilDate, Double)], lowest: Bool = false) {
            // Ties go to the earliest day, which set the record first.
            let sorted = values.sorted { $0.0 < $1.0 }
            guard let pick = (lowest ? sorted.min { $0.1 < $1.1 } : sorted.max { $0.1 < $1.1 }) else { return }
            let winner = sorted.first { $0.1 == pick.1 } ?? pick
            result.append(PersonalRecord(kind: kind, value: winner.1, date: winner.0))
        }
        best(.mostSteps, records.compactMap { r in r.steps.map { (r.date, Double($0)) } })
        best(.mostAZM, records.compactMap { r in r.activeZoneMinutes.map { (r.date, Double($0)) } })
        best(.longestSleep, records.compactMap { r in r.sleep.map { (r.date, Double($0.minutesAsleep)) } })
        best(.highestHRV, records.compactMap { r in r.hrvMs.map { (r.date, $0) } })
        best(.lowestRestingHR, records.compactMap { r in r.restingHeartRate.map { (r.date, $0) } }, lowest: true)
        best(.bestRecovery, scores.compactMap { s in s.recovery.score.map { (s.date, Double($0.total)) } })

        let streakEntries = StreakKind.allCases.flatMap { kind in
            Streaks.history(kind, scores: scores, today: today).map { ($0.date, Double($0.state.current)) }
        }
        best(.longestStreak, streakEntries.filter { $0.1 > 0 })
        return result
    }
}
