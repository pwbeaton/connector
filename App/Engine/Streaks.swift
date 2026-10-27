import Foundation

nonisolated enum StreakKind: String, Codable, Sendable, CaseIterable {
    case sleep, steps, effort

    var title: String {
        switch self {
        case .sleep: "Sleep goal"
        case .steps: "Step goal"
        case .effort: "Effort on target"
        }
    }

    func met(in scores: DayScores) -> Bool? {
        switch self {
        case .sleep: scores.sleepGoalMet
        case .steps: scores.stepGoalMet
        case .effort: scores.effortOnTarget
        }
    }
}

nonisolated struct StreakState: Codable, Equatable, Sendable {
    var current = 0
    var best = 0
    /// Banked rest tokens; each one covers a missed day without breaking the streak.
    var restTokens = 0
    var restTokensUsed = 0
    /// Whether today already counts (goals for today can still be reached).
    var countedToday = false
}

nonisolated enum Streaks {
    /// Rules:
    /// - A met day adds 1. Every 7th day in a row earns a rest token (bank up to 2).
    /// - A missed day spends a rest token if there is one; otherwise the streak resets.
    /// - Today only counts once met; it can't break a streak because the day isn't over.
    /// - A day with no data stays "pending" for 2 days (late syncs), then counts as missed.
    static func compute(_ kind: StreakKind, scores: [DayScores], today: CivilDate) -> StreakState {
        history(kind, scores: scores, today: today).last?.state ?? StreakState()
    }

    /// The streak state at the end of each day, oldest first (used for badges).
    static func history(_ kind: StreakKind, scores: [DayScores], today: CivilDate) -> [(date: CivilDate, state: StreakState)] {
        let byDate = Dictionary(scores.map { ($0.date, kind.met(in: $0)) }, uniquingKeysWith: { first, _ in first })
        guard let start = scores.filter({ kind.met(in: $0) != nil }).map(\.date).min(), start <= today else {
            return []
        }

        var state = StreakState()
        var result: [(date: CivilDate, state: StreakState)] = []
        for date in start.through(today) {
            let met = byDate[date] ?? nil
            if date == today {
                if met == true {
                    countMetDay(&state)
                    state.countedToday = true
                }
            } else if met == nil && date.days(until: today) <= ScoreTuning.pendingDataDays {
                // Data may still arrive; neither count nor break.
            } else if met == true {
                countMetDay(&state)
            } else if state.restTokens > 0 {
                state.restTokens -= 1
                state.restTokensUsed += 1
            } else {
                state.current = 0
            }
            result.append((date, state))
        }
        return result
    }

    private static func countMetDay(_ state: inout StreakState) {
        state.current += 1
        state.best = max(state.best, state.current)
        if state.current.isMultiple(of: ScoreTuning.restTokenEveryDays) {
            state.restTokens = min(ScoreTuning.maxRestTokens, state.restTokens + 1)
        }
    }
}
