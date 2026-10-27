import Foundation
@testable import App

/// Monday, 2026-03-02 (week index 113). US daylight saving starts Sunday 2026-03-08.
let monday = CivilDate(year: 2026, month: 3, day: 2)

extension CivilDate {
    func plus(_ days: Int) -> CivilDate { adding(days: days) }
}

/// A day record with only the fields a test cares about.
func day(_ date: CivilDate, steps: Int? = nil, azm: Int? = nil, hrv: Double? = nil, restingHR: Double? = nil,
         asleep: Int? = nil, wakeMinute: Int = 400, meters: Double? = nil) -> DayRecord {
    DayRecord(date: date, steps: steps, distanceMeters: meters, activeZoneMinutes: azm, restingHeartRate: restingHR,
              hrvMs: hrv, sleep: asleep.map { DemoData.night(wakingOn: date, wakeMinute: wakeMinute, asleepMinutes: $0) })
}

/// Scores with only goal results set (for streak and tier tests).
func goals(_ date: CivilDate, sleep: Bool? = nil, steps: Bool? = nil, effort: Bool? = nil,
           recovery: Recovery = .unavailable) -> DayScores {
    DayScores(date: date, recovery: recovery, sleep: nil, effort: nil, effortTarget: 40...60,
              sleepGoalMet: sleep, stepGoalMet: steps, effortOnTarget: effort)
}

func scored(_ total: Int) -> Recovery {
    .scored(RecoveryScore(total: total, band: RecoveryBand(score: total), hrvComponent: Double(total),
                          restingHRComponent: nil, sleepComponent: nil))
}
