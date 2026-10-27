import Foundation

/// Deterministic sample data that looks like a real Fitbit Air wearer, for demo
/// mode, SwiftUI previews, CI screenshots, and tests. No randomness: the same
/// dates always produce the same numbers.
nonisolated enum DemoData {
    /// US Eastern daylight time, so wake times read naturally in screenshots.
    static let utcOffsetSeconds = -4 * 3600

    /// `days` of history ending on `today`. Today has last night's sleep and a
    /// morning's worth of steps.
    static func records(endingOn today: CivilDate, days: Int = 90, profile: Profile = .you) -> [DayRecord] {
        let start = today.adding(days: -(days - 1))
        var previousEffortAZM = 20
        return start.through(today).map { date in
            let n = Double(date.dayNumber) + profile.phase
            let weekday = date.isoWeekday
            let isWeekend = weekday >= 6
            // Workouts on Mon / Wed / Fri / Sat, plus a few random-looking extras.
            let isWorkoutDay = [1, 3, 5, 6].contains(weekday) || wave(n, 3.1) > 0.85
            // A few rough nights a month (late night out, poor sleep): the "Recover" days.
            let isRoughNight = wave(n, 4.7) > 0.85

            // Sleep: longer on weekends, shorter after hard days.
            let asleep = Int(profile.sleepMinutes + 25 * wave(n, 1.7) + (isWeekend ? 35 : 0)
                - Double(previousEffortAZM) * 0.15 - (isRoughNight ? 80 : 0))
            let wakeMinute = profile.wakeMinute + (isWeekend ? 50 : 0) + Int(12 * wave(n, 2.3))
            let sleep = night(wakingOn: date, wakeMinute: wakeMinute, asleepMinutes: asleep,
                              deepShare: 0.16 + 0.03 * wave(n, 0.9), remShare: 0.22 + 0.03 * wave(n, 1.3),
                              efficiency: 0.90 + 0.04 * wave(n, 2.9))

            // HRV and resting HR respond to sleep and the previous day's effort.
            let strain = Double(previousEffortAZM) / 60
            let sleepDebt = Double(450 - asleep) / 60
            let hrv = profile.hrv * (1 + 0.10 * wave(n, 0.7) - 0.08 * strain - 0.05 * sleepDebt) * (isRoughNight ? 0.8 : 1)
            let restingHR = profile.restingHR + 1.5 * wave(n, 1.1) + 1.8 * strain + 0.8 * sleepDebt + (isRoughNight ? 4 : 0)

            let azm = isWorkoutDay ? Int(38 + 18 * wave(n, 0.5) + profile.intensity) : Int(9 + 7 * wave(n, 1.9))
            let steps = Int(profile.steps + 2600 * wave(n, 0.8) + (isWorkoutDay ? 2200 : 0) - (isWeekend ? 900 : 0))
            previousEffortAZM = azm

            if date == today {
                // Morning: last night is complete, the day has only just begun.
                return DayRecord(date: date, steps: Int(Double(steps) * 0.35), distanceMeters: Double(steps) * 0.35 * 0.76,
                                 activeZoneMinutes: azm / 3, restingHeartRate: restingHR.rounded(), hrvMs: hrv.rounded(),
                                 sleep: sleep, vo2Max: profile.vo2Max)
            }
            return DayRecord(date: date, steps: steps, distanceMeters: Double(steps) * 0.76, activeZoneMinutes: azm,
                             restingHeartRate: restingHR.rounded(), hrvMs: hrv.rounded(), sleep: sleep,
                             napMinutes: weekday == 7 ? 25 : nil, vo2Max: profile.vo2Max, respiratoryRate: 14.5 + 0.4 * wave(n, 1.5))
        }
    }

    /// A smooth pseudo-random value in -1...1 that depends only on `n`.
    static func wave(_ n: Double, _ frequency: Double) -> Double {
        sin(n * frequency) * 0.6 + sin(n * frequency * 2.3 + 1.1) * 0.4
    }

    /// Builds a night from a local wake time and minutes asleep (for demo data and tests).
    static func night(wakingOn date: CivilDate, wakeMinute: Int, asleepMinutes: Int, deepShare: Double = 0.17,
                      remShare: Double = 0.22, efficiency: Double = 0.92, utcOffsetSeconds: Int = utcOffsetSeconds) -> SleepSummary {
        let inBed = Int(Double(asleepMinutes) / efficiency)
        let localWakeSeconds = date.dayNumber * 86_400 + wakeMinute * 60
        let end = Date(timeIntervalSince1970: TimeInterval(localWakeSeconds - utcOffsetSeconds))
        let deep = Int(Double(asleepMinutes) * deepShare)
        let rem = Int(Double(asleepMinutes) * remShare)
        return SleepSummary(start: end.addingTimeInterval(-Double(inBed) * 60), end: end,
                            endUTCOffsetSeconds: utcOffsetSeconds, minutesAsleep: asleepMinutes, minutesInBed: inBed,
                            deepMinutes: deep, remMinutes: rem, lightMinutes: asleepMinutes - deep - rem,
                            awakeMinutes: inBed - asleepMinutes)
    }

    /// Personality knobs, so demo friends look different from each other.
    nonisolated struct Profile: Sendable {
        var sleepMinutes: Double
        var wakeMinute: Int
        var hrv: Double
        var restingHR: Double
        var steps: Double
        var intensity: Double
        var vo2Max: Double
        var phase: Double

        static let you = Profile(sleepMinutes: 440, wakeMinute: 6 * 60 + 40, hrv: 58, restingHR: 56,
                                 steps: 8600, intensity: 6, vo2Max: 46, phase: 0)
    }
}
