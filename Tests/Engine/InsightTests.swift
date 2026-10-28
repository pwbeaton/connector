import Foundation
import Testing
@testable import App

struct BiologicalAgeTests {
    /// 30 identical days: a fit, regular sleeper.
    private func fitDays(vo2: Double = 50, restingHR: Double = 52, steps: Int = 11_000, azm: Int = 45,
                         asleep: Int = 460, wakeMinutes: [Int] = [400]) -> [DayRecord] {
        (0..<30).map { offset in
            var record = day(monday.plus(offset), steps: steps, azm: azm, restingHR: restingHR, asleep: asleep,
                             wakeMinute: wakeMinutes[offset % wakeMinutes.count])
            record.vo2Max = vo2
            return record
        }
    }

    @Test func healthyHabitsMakeYouYounger() throws {
        let records = fitDays()
        let result = try #require(BiologicalAge.estimate(on: monday.plus(29), records: records, age: 30, sex: .male))
        #expect(result.biologicalAge < 30)
        #expect(result.contributors.allSatisfy { ($0.years ?? 0) <= 0 })
    }

    @Test func unhealthyHabitsMakeYouOlder() throws {
        let records = fitDays(vo2: 30, restingHR: 78, steps: 3_000, azm: 0, asleep: 330, wakeMinutes: [360, 540, 420, 600])
        let result = try #require(BiologicalAge.estimate(on: monday.plus(29), records: records, age: 30, sex: .male))
        #expect(result.biologicalAge > 35)
        #expect(result.contributors.allSatisfy { ($0.years ?? 0) >= 0 })
    }

    @Test func needsTwoWeeksOfDataAndAnAdultAge() {
        let records = Array(fitDays().prefix(10))
        #expect(BiologicalAge.estimate(on: monday.plus(9), records: records, age: 30, sex: nil) == nil)
        #expect(BiologicalAge.timeline(records: fitDays(), age: nil, sex: nil, today: monday.plus(29)).isEmpty)
        #expect(BiologicalAge.timeline(records: fitDays(), age: 16, sex: nil, today: monday.plus(29)).isEmpty)
    }

    @Test func meetingEveryReferenceIsNeutral() {
        #expect(BiologicalAge.restingHeartRate(Array(repeating: 60, count: 10), sex: .male).years == 0)
        let target = BiologicalAge.vo2Target(age: 30, sex: .female)
        #expect(target == 38)
        #expect(abs(BiologicalAge.vo2Max([target, target, target], age: 30, sex: .female).years ?? 1) < 0.0001)
        #expect(abs(BiologicalAge.activeZoneMinutes(Array(repeating: 150 / 7, count: 7)).years ?? 1) < 0.2)
    }

    @Test func fewerStepsCountAfterSixty() throws {
        let young = try #require(BiologicalAge.steps(Array(repeating: 6_000, count: 10), age: 40).years)
        let older = try #require(BiologicalAge.steps(Array(repeating: 6_000, count: 10), age: 65).years)
        #expect(young > 0)
        #expect(abs(older) < 0.0001)
    }

    @Test func trendComparesWithFourWeeksEarlier() {
        let early = BiologicalAgeResult(date: monday, chronologicalAge: 30, biologicalAge: 31, contributors: [])
        let now = BiologicalAgeResult(date: monday.plus(28), chronologicalAge: 30, biologicalAge: 29.5, contributors: [])
        let trend = BiologicalAge.trend(on: monday.plus(28), in: [monday: early, monday.plus(28): now])
        #expect(trend?.direction == .improving)
        #expect(trend?.change == -1.5)
    }

    @Test func wakeTimeSpreadWrapsAroundMidnight() {
        #expect(BiologicalAge.circularStandardDeviation([1430, 10]) == 10)
    }
}

struct SleepTipTests {
    private let usual = [400, 400, 400, 400]

    @Test func aLateWakeUpNamesYourUsualTime() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 400 + 150, asleepMinutes: 470)
        let score = SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: usual)
        let tip = SleepTip.make(sleep: night, score: score, goalMinutes: 450, recentWakeMinutes: usual)
        #expect(tip.focus == .consistency)
        #expect(tip.title.contains(Format.clock(minuteOfDay: 400)))
        #expect(tip.detail.contains("later"))
    }

    @Test func aShortNightSuggestsABedtime() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 300)
        let score = SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: usual)
        let tip = SleepTip.make(sleep: night, score: score, goalMinutes: 450, recentWakeMinutes: usual,
                                recentAwakeMinutes: [30])
        #expect(tip.focus == .duration)
        // 6:40 AM wake − 7h 30m goal − 30m awake = 10:40 PM.
        #expect(tip.title.contains(Format.clock(minuteOfDay: 22 * 60 + 40)))
    }

    @Test func aPerfectNightSaysKeepItUp() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 480,
                                   deepShare: 0.20, remShare: 0.25, efficiency: 0.96)
        let score = SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: usual)
        #expect(SleepTip.make(sleep: night, score: score, goalMinutes: 450, recentWakeMinutes: usual).focus == .keepItUp)
    }
}

struct ScoreTrendTests {
    private func sleepScores(_ totals: [Int]) -> [DayScores] {
        totals.enumerated().map { index, total in
            DayScores(date: monday.plus(index), recovery: scored(total), sleep: nil, effort: total,
                      effortTarget: 40...60, sleepGoalMet: nil, stepGoalMet: nil, effortOnTarget: nil)
        }
    }

    @Test func dayChangeComparesWithYesterday() {
        let scores = sleepScores([60, 72])
        #expect(ScoreTrend.dayChange(.recovery, on: monday.plus(1), scores: scores) == 12)
        #expect(ScoreTrend.dayChange(.recovery, on: monday, scores: scores) == nil)
    }

    @Test func weekComparisonFindsTheDirection() throws {
        let scores = sleepScores(Array(repeating: 50, count: 7) + Array(repeating: 70, count: 7))
        let week = try #require(ScoreTrend.weekComparison(.recovery, endingOn: monday.plus(13), scores: scores))
        #expect(week.direction == .up)
        #expect(week.change == 20)
    }
}
