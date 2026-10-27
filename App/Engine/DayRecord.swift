import Foundation

/// Everything the app knows about one day, built from Google Health data (or
/// demo data). Every value is optional: nil means "no data", never zero.
nonisolated struct DayRecord: Codable, Equatable, Sendable, Identifiable {
    var date: CivilDate
    var steps: Int?
    var distanceMeters: Double?
    /// Active Zone Minutes, already weighted by Fitbit (cardio and peak count double).
    var activeZoneMinutes: Int?
    var restingHeartRate: Double?
    /// Nightly HRV (RMSSD, milliseconds) from Google's daily-heart-rate-variability.
    var hrvMs: Double?
    /// The main sleep that ended on this date ("last night").
    var sleep: SleepSummary?
    /// Total minutes of naps that ended on this date (not part of the Sleep score).
    var napMinutes: Int?
    var vo2Max: Double?
    var respiratoryRate: Double?

    var id: CivilDate { date }

    init(date: CivilDate, steps: Int? = nil, distanceMeters: Double? = nil, activeZoneMinutes: Int? = nil,
         restingHeartRate: Double? = nil, hrvMs: Double? = nil, sleep: SleepSummary? = nil,
         napMinutes: Int? = nil, vo2Max: Double? = nil, respiratoryRate: Double? = nil) {
        self.date = date
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeZoneMinutes = activeZoneMinutes
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs
        self.sleep = sleep
        self.napMinutes = napMinutes
        self.vo2Max = vo2Max
        self.respiratoryRate = respiratoryRate
    }

    /// True when the day holds no data at all (tracker not worn or not synced).
    var isEmpty: Bool {
        steps == nil && distanceMeters == nil && activeZoneMinutes == nil && restingHeartRate == nil
            && hrvMs == nil && sleep == nil && napMinutes == nil
    }
}

/// One night's main sleep.
nonisolated struct SleepSummary: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    /// The user's UTC offset when they woke up, so wake time is local even when traveling.
    var endUTCOffsetSeconds: Int
    var minutesAsleep: Int
    /// Bedtime to wake time (Google's minutesInSleepPeriod).
    var minutesInBed: Int
    /// Stage minutes; nil for "classic" sleep without stages.
    var deepMinutes: Int?
    var remMinutes: Int?
    var lightMinutes: Int?
    var awakeMinutes: Int?

    var hasStages: Bool { deepMinutes != nil && remMinutes != nil }

    /// Local wake-up time as minutes after midnight (0..<1440).
    var wakeMinuteOfDay: Int {
        let local = Int(end.timeIntervalSince1970.rounded(.down)) + endUTCOffsetSeconds
        let secondsIntoDay = ((local % 86_400) + 86_400) % 86_400
        return secondsIntoDay / 60
    }
}

/// The user's personal goals (stored on the phone and in profile_private).
nonisolated struct Goals: Codable, Equatable, Sendable {
    var sleepMinutes: Int = ScoreTuning.defaultSleepGoalMinutes
    var steps: Int = ScoreTuning.defaultStepGoal
}
