import Foundation

/// Every number that shapes the scores and the game, in one place.
/// docs/SCORES.md explains each one; change them here after a week of real data.
nonisolated enum ScoreTuning {
    // MARK: Goals (defaults the user can change)
    static let defaultSleepGoalMinutes = 450      // 7.5 h
    static let defaultStepGoal = 8_000

    // MARK: Baselines
    /// Days looked back for the personal HRV and resting-HR baselines.
    static let baselineWindowDays = 30
    /// Nights of data needed before Recovery leaves "Calibrating".
    static let baselineMinimumNights = 7

    // MARK: Recovery (weights add up to 1)
    static let recoveryHRVWeight = 0.5
    static let recoveryRestingHRWeight = 0.2
    static let recoverySleepWeight = 0.3
    /// HRV this far above / below baseline (as a fraction) maps to 100 / 0.
    static let hrvFullScaleDeviation = 0.20
    /// Resting HR this many bpm below / above baseline maps to 100 / 0.
    static let restingHRFullScaleBPM = 5.0
    /// Recovery bands: Go at or above, Recover at or below.
    static let recoveryGoMinimum = 67
    static let recoveryRestMaximum = 33

    // MARK: Sleep (weights add up to 100 points)
    static let sleepDurationPoints = 50.0
    static let sleepRestorationPoints = 25.0
    static let sleepEfficiencyPoints = 15.0
    static let sleepConsistencyPoints = 10.0
    /// Deep + REM share of time asleep that earns full restoration points.
    static let restorativeShareTarget = 0.40
    /// Restoration credit for "classic" sleep with no stage data (fraction of the points).
    static let restorationWithoutStages = 0.6
    /// Efficiency (asleep ÷ in bed) mapped linearly from 0 points to full points.
    static let efficiencyFloor = 0.75
    static let efficiencyCeiling = 0.95
    /// Wake time this many minutes from your usual time earns no consistency points.
    static let wakeConsistencyToleranceMinutes = 90.0
    /// Nights of history needed to judge consistency; before that, this share of the points.
    static let wakeConsistencyMinimumNights = 3
    static let consistencyWithoutHistory = 0.7

    // MARK: Effort
    /// Effort = 100 × (1 − e^(−AZM / scale)): 22 AZM ≈ 39, 45 ≈ 63, 90 ≈ 86.
    static let effortScaleAZM = 45.0
    static let effortTargetGo = 60...80
    static let effortTargetSteady = 40...60
    static let effortTargetRecover = 15...35

    // MARK: Streaks
    /// A rest token is earned for every this many days in a row.
    static let restTokenEveryDays = 7
    static let maxRestTokens = 2
    /// A day with no data stays "pending" (not missed) for this many days.
    static let pendingDataDays = 2

    // MARK: Tier (28-day consistency, percent)
    static let tierWindowDays = 28
    static let tierMinimumDays = 7
    static let tierThresholds: [(tier: Tier, minimum: Int)] = [
        (.elite, 92), (.platinum, 82), (.gold, 70), (.silver, 55), (.bronze, 40),
    ]

    // MARK: Challenges
    /// Personal challenges ask for this much more than your 4-week average.
    static let challengeStretch = 1.10
    static let challengeHistoryDays = 28
    /// Minimum weekly Active Zone Minutes target (the WHO's 150 minutes).
    static let challengeMinimumWeeklyAZM = 150
    /// "Nights ≥ 7 h" group challenge threshold.
    static let longNightMinutes = 420
}
