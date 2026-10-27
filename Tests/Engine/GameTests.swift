import Foundation
import Testing
@testable import App

struct StreakTests {
    @Test func countsDaysInARow() {
        let scores = (0..<5).map { goals(monday.plus($0), steps: true) }
        let state = Streaks.compute(.steps, scores: scores, today: monday.plus(5))
        #expect(state.current == 5)
        #expect(state.best == 5)
    }

    @Test func aMissedDayResetsWithoutRestTokens() {
        var scores = (0..<3).map { goals(monday.plus($0), steps: true) }
        scores.append(goals(monday.plus(3), steps: false))
        scores.append(goals(monday.plus(4), steps: true))
        let state = Streaks.compute(.steps, scores: scores, today: monday.plus(5))
        #expect(state.current == 1)
        #expect(state.best == 3)
    }

    @Test func sevenDaysEarnARestTokenThatCoversAMiss() {
        var scores = (0..<7).map { goals(monday.plus($0), steps: true) }
        scores.append(goals(monday.plus(7), steps: false))
        scores.append(goals(monday.plus(8), steps: true))
        let state = Streaks.compute(.steps, scores: scores, today: monday.plus(9))
        #expect(state.current == 8)
        #expect(state.restTokens == 0)
        #expect(state.restTokensUsed == 1)
    }

    @Test func restTokensAreCappedAtTwo() {
        let scores = (0..<21).map { goals(monday.plus($0), sleep: true) }
        let state = Streaks.compute(.sleep, scores: scores, today: monday.plus(21))
        #expect(state.restTokens == 2)
    }

    @Test func todayCountsOnceMetButNeverBreaks() {
        var scores = (0..<3).map { goals(monday.plus($0), effort: true) }
        scores.append(goals(monday.plus(3), effort: false))
        let unmet = Streaks.compute(.effort, scores: scores, today: monday.plus(3))
        #expect(unmet.current == 3)
        #expect(unmet.countedToday == false)

        scores[3] = goals(monday.plus(3), effort: true)
        let met = Streaks.compute(.effort, scores: scores, today: monday.plus(3))
        #expect(met.current == 4)
        #expect(met.countedToday)
    }

    @Test func daysWithoutDataStayPendingForTwoDays() {
        let scores = (0..<3).map { goals(monday.plus($0), steps: true) }
        // Day 3 has no data yet; with today = day 4 it's still pending.
        #expect(Streaks.compute(.steps, scores: scores, today: monday.plus(4)).current == 3)
        // By day 6 it's three days old and counts as missed.
        let later = Streaks.compute(.steps, scores: scores, today: monday.plus(6))
        #expect(later.current == 0)
        #expect(later.best == 3)
    }

    @Test func noDataMeansNoStreak() {
        #expect(Streaks.compute(.sleep, scores: [], today: monday) == StreakState())
    }
}

struct TierTests {
    @Test func calibratesForTheFirstWeek() {
        let scores = (0..<5).map { goals(monday.plus($0), sleep: true, steps: true, effort: true) }
        let state = Tiers.compute(scores: scores, today: monday.plus(5))
        #expect(state.isCalibrating)
        #expect(state.tier == .rookie)
        #expect(state.consistency == 100)
    }

    @Test func perfectConsistencyIsElite() {
        let scores = (0..<28).map { goals(monday.plus($0), sleep: true, steps: true, effort: true) }
        let state = Tiers.compute(scores: scores, today: monday.plus(28))
        #expect(state.daysInWindow == 28)
        #expect(state.tier == .elite)
    }

    @Test func todayIsNotInTheWindow() {
        var scores = (0..<28).map { goals(monday.plus($0), sleep: true, steps: true, effort: true) }
        scores.append(goals(monday.plus(28), sleep: false, steps: false, effort: false))
        #expect(Tiers.compute(scores: scores, today: monday.plus(28)).consistency == 100)
    }

    @Test func missingDaysCountAsMissedGoals() {
        let everyOtherDay = stride(from: 0, to: 28, by: 2).map {
            goals(monday.plus($0), sleep: true, steps: true, effort: true)
        }
        let state = Tiers.compute(scores: everyOtherDay, today: monday.plus(28))
        #expect(state.consistency == 50)
        #expect(state.tier == .bronze)
    }

    @Test func thresholds() {
        #expect(Tier(consistency: 92) == .elite)
        #expect(Tier(consistency: 91) == .platinum)
        #expect(Tier(consistency: 82) == .platinum)
        #expect(Tier(consistency: 70) == .gold)
        #expect(Tier(consistency: 55) == .silver)
        #expect(Tier(consistency: 40) == .bronze)
        #expect(Tier(consistency: 39) == .rookie)
        #expect(Tier.gold > Tier.silver)
        #expect(Tier.elite.next == nil)
    }

    @Test func pointsToTheNextTier() {
        let state = TierState(tier: .silver, consistency: 61, daysInWindow: 28, isCalibrating: false)
        #expect(state.pointsToNextTier == 9)
    }
}

struct ChallengeTests {
    @Test func threeDistinctChallengesThatRotateWeekly() {
        var trios: Set<[ChallengeKind]> = []
        for week in 0..<6 {
            let weekStart = monday.plus(7 * week)
            let kinds = Challenges.personal(weekStart: weekStart, records: [], scores: [], goals: Goals()).map(\.kind)
            #expect(kinds.count == 3)
            #expect(Set(kinds).count == 3)
            trios.insert(kinds)
        }
        #expect(trios.count == 6)
    }

    @Test func stepTargetStretchesYourAverageBy10Percent() {
        // Week 113: offset 113 % 6 = 5 → stepGoalDays, stepsTotal, azmTotal.
        let history = (1...28).map { day(monday.plus(-$0), steps: 10_000) }
        let challenges = Challenges.personal(weekStart: monday, records: history, scores: [], goals: Goals())
        let steps = challenges.first { $0.kind == .stepsTotal }
        #expect(steps?.target == 77_000)
    }

    @Test func progressCountsOnlyThisWeek() {
        let records = [day(monday.plus(-1), steps: 50_000), day(monday, steps: 9_000), day(monday.plus(1), steps: 11_000)]
        let challenges = Challenges.personal(weekStart: monday, records: records, scores: [], goals: Goals())
        #expect(challenges.first { $0.kind == .stepsTotal }?.progress == 20_000)
    }

    @Test func activeZoneMinuteTargetIsAtLeast150() {
        // Week 114: offset 0 → stepsTotal, sleepGoalNights, effortTargetDays; week 115: offset 1 includes azmTotal.
        let weekStart = monday.plus(14)
        let history = (1...28).map { day(weekStart.plus(-$0), azm: 5) }
        let azm = Challenges.personal(weekStart: weekStart, records: history, scores: [], goals: Goals())
            .first { $0.kind == .azmTotal }
        #expect(azm?.target == 150)
    }

    @Test func groupChallengeRotatesLikeTheServer() {
        // The server uses ((week_start - 2024-01-01) / 7) % 4 in the same order.
        #expect(Challenges.group(for: CivilDate(year: 2024, month: 1, day: 1)) == .steps)
        #expect(Challenges.group(for: CivilDate(year: 2024, month: 1, day: 8)) == .activeZoneMinutes)
        #expect(Challenges.group(for: monday) == .activeZoneMinutes) // week 113 % 4 = 1
        #expect(Challenges.group(for: monday.plus(7)) == .longNights)
    }

    @Test func groupValueIsNilWithoutData() {
        #expect(Challenges.groupValue(.steps, weekStart: monday, records: []) == nil)
        let records = [day(monday, asleep: 400), day(monday.plus(1), asleep: 440)]
        #expect(Challenges.groupValue(.averageSleep, weekStart: monday, records: records) == 420)
        #expect(Challenges.groupValue(.longNights, weekStart: monday, records: records) == 1)
    }
}

struct BadgeTests {
    @Test func noDataNoBadges() {
        #expect(Badges.earned(records: [], scores: [], today: monday).isEmpty)
    }

    @Test func first10KIsDatedTheDayItHappened() {
        let records = [day(monday, steps: 9_000), day(monday.plus(1), steps: 10_500), day(monday.plus(2), steps: 12_000)]
        let badges = Badges.earned(records: records, scores: [], today: monday.plus(2))
        #expect(badges.first { $0.id == "first-10k" }?.earnedOn == monday.plus(1))
        #expect(badges.first { $0.id == "day-one" }?.earnedOn == monday)
        #expect(!badges.contains { $0.id == "20k-club" })
    }

    @Test func ironWeekNeedsSevenSleepGoalNights() {
        let scores = (0..<7).map { goals(monday.plus($0), sleep: true) }
        let badges = Badges.earned(records: [], scores: scores, today: monday.plus(7))
        #expect(badges.first { $0.id == "iron-week" }?.earnedOn == monday.plus(6))
    }

    @Test func bounceBackIsRecoverThenGo() {
        let scores = [goals(monday, recovery: scored(20)), goals(monday.plus(1), recovery: scored(80))]
        let badges = Badges.earned(records: [], scores: scores, today: monday.plus(1))
        #expect(badges.contains { $0.id == "bounce-back" })
        #expect(badges.contains { $0.id == "calibrated" })
    }

    @Test func everyBadgeHasAUniqueID() {
        #expect(Set(Badges.all.map(\.id)).count == Badges.all.count)
        #expect(Badges.all.count == 20)
    }
}

struct RecordTests {
    @Test func tiesGoToTheEarliestDay() {
        let records = [day(monday, steps: 12_000), day(monday.plus(1), steps: 12_000), day(monday.plus(2), steps: 8_000)]
        let most = Records.compute(records: records, scores: [], today: monday.plus(2)).first { $0.kind == .mostSteps }
        #expect(most?.value == 12_000)
        #expect(most?.date == monday)
    }

    @Test func lowestRestingHeartRate() {
        let records = [day(monday, restingHR: 58), day(monday.plus(1), restingHR: 52), day(monday.plus(2), restingHR: 55)]
        let lowest = Records.compute(records: records, scores: [], today: monday.plus(2)).first { $0.kind == .lowestRestingHR }
        #expect(lowest?.value == 52)
        #expect(lowest?.date == monday.plus(1))
    }
}

struct EngineTests {
    private let today = CivilDate(year: 2026, month: 10, day: 27)

    @Test func demoDataProducesAFullSnapshot() {
        let records = DemoData.records(endingOn: today)
        let snapshot = Engine.run(records: records, goals: Goals(), today: today)
        #expect(snapshot.days.count == 90)
        #expect(snapshot.todayScores?.recovery.score != nil)
        #expect(snapshot.tier.isCalibrating == false)
        #expect(snapshot.challenges.count == 3)
        #expect(snapshot.badges.contains { $0.id == "day-one" })
        #expect(snapshot.badges.contains { $0.id == "calibrated" })
        #expect(snapshot.records.count == RecordKind.allCases.count)
        #expect(snapshot.hrvNightsCollected >= 30)
    }

    @Test func demoScoresLookRealistic() {
        let snapshot = Engine.run(records: DemoData.records(endingOn: today), goals: Goals(), today: today)
        let recoveries = snapshot.days.compactMap { $0.recovery.score?.total }
        let bands = Set(snapshot.days.compactMap { $0.recovery.score?.band })
        #expect(recoveries.allSatisfy { (0...100).contains($0) })
        #expect(bands.count == 3, "demo data should show every Recovery band at least once")
        let sleeps = snapshot.days.compactMap { $0.sleep?.total }
        #expect(sleeps.allSatisfy { (40...100).contains($0) })
    }

    @Test func futureRecordsAreIgnored() {
        let records = [day(today, steps: 5_000), day(today.plus(1), steps: 50_000)]
        let snapshot = Engine.run(records: records, goals: Goals(), today: today)
        #expect(snapshot.days.map(\.date) == [today])
    }

    @Test func demoDataIsDeterministic() {
        #expect(DemoData.records(endingOn: today) == DemoData.records(endingOn: today))
        let records = DemoData.records(endingOn: today)
        #expect(records.count == 90)
        #expect(records.last?.date == today)
        #expect((records.last?.steps ?? 0) < (records.dropLast().last?.steps ?? 0) + 10_000)
    }
}
