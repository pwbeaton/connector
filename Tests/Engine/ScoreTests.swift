import Foundation
import Testing
@testable import App

struct SleepScoreTests {
    private let onTime = [400, 400, 400]

    @Test func aGreatNightScores100() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 480,
                                   deepShare: 0.20, remShare: 0.25, efficiency: 0.96)
        let score = SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: onTime)
        #expect(score.total == 100)
    }

    @Test func durationLosesPointsFasterAsTheShortfallGrows() {
        let half = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 225)
        let ninety = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 405)
        #expect(SleepScore.score(half, goalMinutes: 450, recentWakeMinutes: onTime).duration == 12.5)
        #expect(abs(SleepScore.score(ninety, goalMinutes: 450, recentWakeMinutes: onTime).duration - 40.5) < 0.0001)
    }

    @Test func nightsWithoutStagesGetPartialRestoration() {
        var night = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 450)
        night.deepMinutes = nil
        night.remMinutes = nil
        let score = SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: onTime)
        #expect(score.restoration == 25 * 0.5)
    }

    @Test func efficiencyRunsFrom80To95Percent() {
        let restless = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 400, efficiency: 0.79)
        let solid = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 400, efficiency: 0.97)
        #expect(SleepScore.score(restless, goalMinutes: 450, recentWakeMinutes: onTime).efficiency == 0)
        #expect(SleepScore.score(solid, goalMinutes: 450, recentWakeMinutes: onTime).efficiency == 15)
    }

    @Test func consistencyNeedsThreeNightsOfHistory() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 450)
        #expect(SleepScore.score(night, goalMinutes: 450, recentWakeMinutes: [400]).consistency == 7)
    }

    @Test func consistencyFallsWithDistanceFromYourUsualWakeTime() {
        let usual = DemoData.night(wakingOn: monday, wakeMinute: 400, asleepMinutes: 450)
        let late = DemoData.night(wakingOn: monday, wakeMinute: 490, asleepMinutes: 450)
        #expect(SleepScore.score(usual, goalMinutes: 450, recentWakeMinutes: onTime).consistency == 10)
        #expect(SleepScore.score(late, goalMinutes: 450, recentWakeMinutes: onTime).consistency == 0)
    }

    @Test func clockMathWrapsAroundMidnight() {
        #expect(SleepScore.circularMeanMinute([1430, 10]) == 0)
        #expect(SleepScore.circularDistance(1430, 10) == 20)
        #expect(SleepScore.circularDistance(400, 460) == 60)
    }
}

struct BaselineTests {
    @Test func needsSevenNightsBeforeItExists() {
        let six = (0..<6).map { day(monday.plus($0), hrv: 50) }
        #expect(Baselines.baseline(for: monday.plus(6), in: six) { $0.hrvMs } == nil)
        #expect(Baselines.nightsCollected(before: monday.plus(6), in: six) { $0.hrvMs } == 6)

        let seven = (0..<7).map { day(monday.plus($0), hrv: 50) }
        #expect(Baselines.baseline(for: monday.plus(7), in: seven) { $0.hrvMs } == Baseline(median: 50, nights: 7))
    }

    @Test func usesTheMedian() {
        #expect(Baselines.median([3, 1, 2]) == 2)
        #expect(Baselines.median([4, 1, 2, 3]) == 2.5)
    }

    @Test func excludesTheDayItselfAndDaysOlderThan30() {
        var records = (1...7).map { day(monday.plus($0), hrv: 60) }
        records.append(day(monday.plus(-40), hrv: 10))   // too old
        records.append(day(monday.plus(8), hrv: 999))    // the day being scored
        let baseline = Baselines.baseline(for: monday.plus(8), in: records) { $0.hrvMs }
        #expect(baseline == Baseline(median: 60, nights: 7))
    }
}

struct RecoveryTests {
    private let baseline = Baseline(median: 50, nights: 20)
    private let restingBaseline = Baseline(median: 55, nights: 20)

    @Test func calibratesUntilThereIsABaseline() {
        let result = RecoveryScore.compute(hrv: 50, hrvBaseline: nil, hrvNightsCollected: 4,
                                           restingHR: 55, restingHRBaseline: nil, sleepScore: 80)
        #expect(result == .calibrating(nightsCollected: 4))
    }

    @Test func isUnavailableWithoutLastNightsHRV() {
        let result = RecoveryScore.compute(hrv: nil, hrvBaseline: baseline, hrvNightsCollected: 20,
                                           restingHR: 55, restingHRBaseline: restingBaseline, sleepScore: 80)
        #expect(result == .unavailable)
    }

    @Test func anAverageNightIsSteady() {
        // 0.5 × 50 + 0.2 × 50 + 0.3 × 80 = 59
        let score = RecoveryScore.compute(hrv: 50, hrvBaseline: baseline, hrvNightsCollected: 20,
                                          restingHR: 55, restingHRBaseline: restingBaseline, sleepScore: 80).score
        #expect(score?.total == 59)
        #expect(score?.band == .steady)
    }

    @Test func hrvComponentSpansPlusMinus20Percent() {
        let high = RecoveryScore.compute(hrv: 60, hrvBaseline: baseline, hrvNightsCollected: 20,
                                         restingHR: nil, restingHRBaseline: nil, sleepScore: nil).score
        let low = RecoveryScore.compute(hrv: 30, hrvBaseline: baseline, hrvNightsCollected: 20,
                                        restingHR: nil, restingHRBaseline: nil, sleepScore: nil).score
        #expect(high?.hrvComponent == 100)
        #expect(high?.total == 100)
        #expect(low?.hrvComponent == 0)
        #expect(low?.band == .recover)
    }

    @Test func restingHRComponentSpansPlusMinus5BPM() {
        let calm = RecoveryScore.compute(hrv: 50, hrvBaseline: baseline, hrvNightsCollected: 20,
                                         restingHR: 50, restingHRBaseline: restingBaseline, sleepScore: nil).score
        let elevated = RecoveryScore.compute(hrv: 50, hrvBaseline: baseline, hrvNightsCollected: 20,
                                             restingHR: 62, restingHRBaseline: restingBaseline, sleepScore: nil).score
        #expect(calm?.restingHRComponent == 100)
        #expect(elevated?.restingHRComponent == 0)
    }

    @Test func missingInputsAreReweighted() {
        // No resting HR: (0.5 × 50 + 0.3 × 80) / 0.8 = 61.25 → 61
        let score = RecoveryScore.compute(hrv: 50, hrvBaseline: baseline, hrvNightsCollected: 20,
                                          restingHR: nil, restingHRBaseline: restingBaseline, sleepScore: 80).score
        #expect(score?.total == 61)
        #expect(score?.restingHRComponent == nil)
    }

    @Test func bandThresholds() {
        #expect(RecoveryBand(score: 67) == .go)
        #expect(RecoveryBand(score: 66) == .steady)
        #expect(RecoveryBand(score: 34) == .steady)
        #expect(RecoveryBand(score: 33) == .recover)
    }

    @Test func effortTargetFollowsTheBand() {
        #expect(RecoveryBand.go.effortTarget == 60...80)
        #expect(RecoveryBand.steady.effortTarget == 40...60)
        #expect(RecoveryBand.recover.effortTarget == 15...35)
    }
}

struct EffortTests {
    @Test func scoreCurve() {
        #expect(Effort.score(activeZoneMinutes: 0) == 0)
        #expect(Effort.score(activeZoneMinutes: 22) == 39)
        #expect(Effort.score(activeZoneMinutes: 45) == 63)
        #expect(Effort.score(activeZoneMinutes: 90) == 86)
        #expect(Effort.score(activeZoneMinutes: 1000) == 100)
        #expect(Effort.score(activeZoneMinutes: -5) == 0)
    }

    @Test func minutesNeededForAScore() {
        #expect(Effort.activeZoneMinutes(forScore: 63) == 45)
        #expect(Effort.score(activeZoneMinutes: Effort.activeZoneMinutes(forScore: 60)) >= 60)
    }

    @Test func statusAgainstTheTarget() {
        #expect(Effort.status(score: 30, target: 40...60) == .below)
        #expect(Effort.status(score: 40, target: 40...60) == .onTarget)
        #expect(Effort.status(score: 61, target: 40...60) == .above)
    }
}

struct DailyScoringTests {
    @Test func missingDataIsNotAMissedGoal() {
        let scores = DailyScoring.score([day(monday, steps: 9000)], goals: Goals())
        #expect(scores.first?.stepGoalMet == true)
        #expect(scores.first?.sleepGoalMet == nil)
        #expect(scores.first?.effortOnTarget == nil)
    }

    @Test func goalsUseTheUsersSettings() {
        let scores = DailyScoring.score([day(monday, steps: 9000, asleep: 400)],
                                        goals: Goals(sleepMinutes: 420, steps: 10_000))
        #expect(scores.first?.stepGoalMet == false)
        #expect(scores.first?.sleepGoalMet == false)
    }

    @Test func calibratingDaysAimForTheSteadyTarget() {
        let scores = DailyScoring.score([day(monday, azm: 30, hrv: 50)], goals: Goals())
        #expect(scores.first?.recovery == .calibrating(nightsCollected: 0))
        #expect(scores.first?.effortTarget == 40...60)
        #expect(scores.first?.effort == 49)
        #expect(scores.first?.effortOnTarget == true)
    }

    @Test func goingOverTheTargetOnARecoverDayDoesNotCount() {
        // Seven calm nights, then a night with HRV 40% down → Recover; then a hard day.
        var records = (0..<7).map { day(monday.plus($0), hrv: 60, restingHR: 50) }
        records.append(day(monday.plus(7), azm: 120, hrv: 36, restingHR: 58))
        let last = DailyScoring.score(records, goals: Goals()).last
        #expect(last?.recovery.score?.band == .recover)
        #expect(last?.effortOnTarget == false)
    }

    @Test func goingOverTheTargetOnAGoDayStillCounts() {
        var records = (0..<7).map { day(monday.plus($0), hrv: 50, restingHR: 55) }
        records.append(day(monday.plus(7), azm: 150, hrv: 62, restingHR: 50))
        let last = DailyScoring.score(records, goals: Goals()).last
        #expect(last?.recovery.score?.band == .go)
        #expect(last?.effortOnTarget == true)
    }
}
