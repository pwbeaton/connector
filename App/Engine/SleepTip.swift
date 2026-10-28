import Foundation

/// One concrete thing to do tonight, aimed at the part of the Sleep score that lost
/// the most points last night.
nonisolated struct SleepTip: Equatable, Sendable {
    nonisolated enum Focus: String, Sendable {
        case duration, consistency, efficiency, restoration, keepItUp
    }

    let focus: Focus
    /// Short headline, e.g. "Wake closer to 6:45 AM".
    let title: String
    /// One or two sentences with your numbers.
    let detail: String

    var symbol: String {
        switch focus {
        case .duration: "bed.double.fill"
        case .consistency: "alarm.fill"
        case .efficiency: "moon.zzz.fill"
        case .restoration: "sparkles"
        case .keepItUp: "checkmark.seal.fill"
        }
    }

    /// - Parameters:
    ///   - recentWakeMinutes: local wake times of the 7 nights before this one.
    ///   - recentAwakeMinutes: minutes awake in bed on recent nights (to plan a bedtime).
    /// - Parameter plannedBedtime: tonight's bedtime from the sleep-debt plan, so the tip and the plan agree.
    static func make(sleep: SleepSummary, score: SleepScore, goalMinutes: Int, recentWakeMinutes: [Int],
                     recentAwakeMinutes: [Int] = [], plannedBedtime: Int? = nil) -> SleepTip {
        let usualWake = recentWakeMinutes.count >= ScoreTuning.wakeConsistencyMinimumNights
            ? SleepScore.circularMeanMinute(recentWakeMinutes) : nil

        // Points lost per part of the score; parts the data can't speak to are skipped.
        var lost: [(Focus, Double)] = [
            (.duration, ScoreTuning.sleepDurationPoints - score.duration),
            (.efficiency, ScoreTuning.sleepEfficiencyPoints - score.efficiency),
        ]
        if usualWake != nil { lost.append((.consistency, ScoreTuning.sleepConsistencyPoints - score.consistency)) }
        if sleep.hasStages { lost.append((.restoration, ScoreTuning.sleepRestorationPoints - score.restoration)) }
        let worst = lost.max { $0.1 < $1.1 }

        guard let worst, worst.1 >= 2 else {
            let wake = usualWake.map { " Keep waking near \(Format.clock(minuteOfDay: $0)) to lock it in." } ?? ""
            return SleepTip(focus: .keepItUp, title: "Great night",
                            detail: "You hit every part of your Sleep score.\(wake)")
        }

        switch worst.0 {
        case .duration:
            let short = max(0, goalMinutes - sleep.minutesAsleep)
            let awake = recentAwakeMinutes.isEmpty
                ? max(0, sleep.minutesInBed - sleep.minutesAsleep)
                : recentAwakeMinutes.reduce(0, +) / recentAwakeMinutes.count
            let wake = usualWake ?? sleep.wakeMinuteOfDay
            let bedtime = plannedBedtime ?? ((wake - goalMinutes - awake) % 1440 + 1440) % 1440
            return SleepTip(
                focus: .duration,
                title: "In bed by \(Format.clock(minuteOfDay: bedtime))",
                detail: "You slept \(Format.duration(minutes: sleep.minutesAsleep)), \(Format.duration(minutes: short)) short of your \(Format.duration(minutes: goalMinutes)) goal. To wake at \(Format.clock(minuteOfDay: wake)) with a full night, aim to be in bed by \(Format.clock(minuteOfDay: bedtime))."
            )
        case .consistency:
            let usual = usualWake ?? sleep.wakeMinuteOfDay
            let woke = sleep.wakeMinuteOfDay
            let gap = SleepScore.circularDistance(woke, usual)
            let later = ((woke - usual + 1440) % 1440) < 720
            return SleepTip(
                focus: .consistency,
                title: "Wake closer to \(Format.clock(minuteOfDay: usual))",
                detail: "You woke at \(Format.clock(minuteOfDay: woke)), \(Format.duration(minutes: gap)) \(later ? "later" : "earlier") than your usual \(Format.clock(minuteOfDay: usual)). Getting up within 30 minutes of \(Format.clock(minuteOfDay: usual)), weekends included, keeps your body clock steady."
            )
        case .efficiency:
            let awake = max(0, sleep.minutesInBed - sleep.minutesAsleep)
            let percent = sleep.minutesInBed > 0 ? Int((Double(sleep.minutesAsleep) / Double(sleep.minutesInBed) * 100).rounded()) : 0
            return SleepTip(
                focus: .efficiency,
                title: "Less time awake in bed",
                detail: "You were awake for \(Format.duration(minutes: awake)) of \(Format.duration(minutes: sleep.minutesInBed)) in bed (\(percent)% efficiency). If you can't fall asleep within about 20 minutes, get up and do something calm in dim light until you feel sleepy."
            )
        case .restoration:
            let deepAndREM = (sleep.deepMinutes ?? 0) + (sleep.remMinutes ?? 0)
            let percent = sleep.minutesAsleep > 0 ? Int((Double(deepAndREM) / Double(sleep.minutesAsleep) * 100).rounded()) : 0
            return SleepTip(
                focus: .restoration,
                title: "More deep and REM sleep",
                detail: "Deep and REM were \(percent)% of your night (\(Int(ScoreTuning.restorativeShareTarget * 100))% earns full points). Skip alcohol and big meals in the 3 hours before bed, and keep your room cool, around 65°F (18°C)."
            )
        case .keepItUp:
            return SleepTip(focus: .keepItUp, title: "Great night", detail: "You hit every part of your Sleep score.")
        }
    }
}
