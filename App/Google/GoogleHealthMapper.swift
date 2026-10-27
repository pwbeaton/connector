import Foundation

/// Raw-ish results of one fetch, keyed by the user's civil date.
nonisolated struct HealthFetch: Sendable {
    var steps: [CivilDate: Int] = [:]
    var distanceMeters: [CivilDate: Double] = [:]
    var activeZoneMinutes: [CivilDate: Int] = [:]
    var restingHeartRate: [CivilDate: Double] = [:]
    var hrvMs: [CivilDate: Double] = [:]
    var vo2Max: [CivilDate: Double] = [:]
    var respiratoryRate: [CivilDate: Double] = [:]
    var sleeps: [SleepDTO] = []
}

/// Turns Google Health responses into the app's DayRecords.
nonisolated enum GoogleHealthMapper {
    static func addRollups(_ points: [DailyRollupDataPointDTO], to fetch: inout HealthFetch) {
        for point in points {
            guard let date = point.civilStartTime?.date.civil else { continue }
            if let steps = point.steps?.countSum?.value { fetch.steps[date] = steps }
            if let millimeters = point.distance?.millimetersSum?.value { fetch.distanceMeters[date] = Double(millimeters) / 1000 }
            if let azm = point.activeZoneMinutes {
                let parts = [azm.sumInFatBurnHeartZone, azm.sumInCardioHeartZone, azm.sumInPeakHeartZone].compactMap { $0?.value }
                if !parts.isEmpty { fetch.activeZoneMinutes[date] = parts.reduce(0, +) }
            }
        }
    }

    static func addDailyValues(_ points: [DataPointDTO], to fetch: inout HealthFetch) {
        for point in points {
            if let rhr = point.dailyRestingHeartRate, let bpm = rhr.beatsPerMinute?.value, bpm > 0 {
                fetch.restingHeartRate[rhr.date.civil] = Double(bpm)
            }
            if let hrv = point.dailyHeartRateVariability, let ms = hrv.averageHeartRateVariabilityMilliseconds, ms > 0 {
                fetch.hrvMs[hrv.date.civil] = ms
            }
            if let vo2 = point.dailyVo2Max, let value = vo2.vo2Max, value > 0 {
                fetch.vo2Max[vo2.date.civil] = value
            }
            if let breathing = point.dailyRespiratoryRate, let value = breathing.breathsPerMinute, value > 0 {
                fetch.respiratoryRate[breathing.date.civil] = value
            }
            if let sleep = point.sleep {
                fetch.sleeps.append(sleep)
            }
        }
    }

    /// One parsed sleep session.
    nonisolated struct Night: Sendable {
        let date: CivilDate
        let isMain: Bool
        let isNap: Bool
        let summary: SleepSummary
    }

    static func night(from dto: SleepDTO) -> Night? {
        guard let start = GoogleTime.date(from: dto.interval.startTime),
              let end = GoogleTime.date(from: dto.interval.endTime),
              let asleep = dto.summary?.minutesAsleep?.value
        else { return nil }
        let offset = dto.interval.endUtcOffset.flatMap(GoogleTime.seconds(fromDuration:)) ?? 0
        // The night belongs to the civil date you woke up.
        let date = dto.interval.civilEndTime?.date.civil
            ?? CivilDate(dayNumber: Int(((end.timeIntervalSince1970 + Double(offset)) / 86_400).rounded(.down)))

        let stages = Dictionary((dto.summary?.stagesSummary ?? []).compactMap { stage -> (String, Int)? in
            guard let type = stage.type, let minutes = stage.minutes?.value else { return nil }
            return (type, minutes)
        }, uniquingKeysWith: +)
        let hasStages = dto.type == "STAGES" || stages["DEEP"] != nil || stages["REM"] != nil

        let inBed = dto.summary?.minutesInSleepPeriod?.value ?? Int(end.timeIntervalSince(start) / 60)
        let summary = SleepSummary(
            start: start, end: end, endUTCOffsetSeconds: offset,
            minutesAsleep: asleep, minutesInBed: max(inBed, asleep),
            deepMinutes: hasStages ? stages["DEEP"] ?? 0 : nil,
            remMinutes: hasStages ? stages["REM"] ?? 0 : nil,
            lightMinutes: hasStages ? stages["LIGHT"] ?? 0 : nil,
            awakeMinutes: stages["AWAKE"] ?? dto.summary?.minutesAwake?.value
        )
        return Night(date: date, isMain: dto.metadata?.mainSleep == true, isNap: dto.metadata?.nap == true, summary: summary)
    }

    /// Builds a DayRecord for every date in `dates` that has any data.
    static func records(from fetch: HealthFetch, dates: [CivilDate]) -> [DayRecord] {
        let nights = fetch.sleeps.compactMap(night(from:))
        let nightsByDate = Dictionary(grouping: nights, by: \.date)

        return dates.compactMap { date in
            let sessions = nightsByDate[date] ?? []
            // The main sleep: Google's pick, else the longest session that isn't a nap.
            let main = sessions.first { $0.isMain }
                ?? sessions.filter { !$0.isNap }.max { $0.summary.minutesAsleep < $1.summary.minutesAsleep }
            let naps = sessions.filter { $0.isNap && $0.summary != main?.summary }.map(\.summary.minutesAsleep)

            let record = DayRecord(
                date: date,
                steps: fetch.steps[date],
                distanceMeters: fetch.distanceMeters[date],
                activeZoneMinutes: fetch.activeZoneMinutes[date],
                restingHeartRate: fetch.restingHeartRate[date],
                hrvMs: fetch.hrvMs[date],
                sleep: main?.summary,
                napMinutes: naps.isEmpty ? nil : naps.reduce(0, +),
                vo2Max: fetch.vo2Max[date],
                respiratoryRate: fetch.respiratoryRate[date]
            )
            return record.isEmpty ? nil : record
        }
    }
}
