import Foundation

// Decodable shapes for the Google Health API v4 responses the app reads.
// Field names follow the API description (discovery doc revision 20261023).
// Only the fields we use are declared; everything else is ignored.
// Google sends 64-bit integers as strings, so they're decoded with FlexibleInt.

/// An integer that may arrive as a JSON number or a string ("8423").
nonisolated struct FlexibleInt: Decodable, Equatable, Sendable {
    let value: Int

    init(_ value: Int) { self.value = value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let string = try? container.decode(String.self), let number = Int(string) {
            value = number
        } else if let double = try? container.decode(Double.self) {
            value = Int(double.rounded())
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer or numeric string")
        }
    }
}

nonisolated struct APIDate: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: CivilDate) {
        year = date.year
        month = date.month
        day = date.day
    }

    var civil: CivilDate { CivilDate(year: year, month: month, day: day) }
}

nonisolated struct APICivilDateTime: Codable, Equatable, Sendable {
    let date: APIDate
}

// MARK: - Daily roll-ups

nonisolated struct DailyRollUpRequestDTO: Encodable, Sendable {
    nonisolated struct Range: Encodable, Sendable {
        let start: APICivilDateTime
        let end: APICivilDateTime
    }
    let range: Range
    let windowSizeDays: Int
    let pageSize: Int
    let pageToken: String?
}

nonisolated struct DailyRollUpResponseDTO: Decodable, Sendable {
    let rollupDataPoints: [DailyRollupDataPointDTO]?
    let nextPageToken: String?
}

nonisolated struct DailyRollupDataPointDTO: Decodable, Sendable {
    nonisolated struct Steps: Decodable, Sendable { let countSum: FlexibleInt? }
    nonisolated struct Distance: Decodable, Sendable { let millimetersSum: FlexibleInt? }
    nonisolated struct ActiveZoneMinutes: Decodable, Sendable {
        let sumInFatBurnHeartZone: FlexibleInt?
        let sumInCardioHeartZone: FlexibleInt?
        let sumInPeakHeartZone: FlexibleInt?
    }

    let civilStartTime: APICivilDateTime?
    let steps: Steps?
    let distance: Distance?
    let activeZoneMinutes: ActiveZoneMinutes?
}

// MARK: - Listed data points

nonisolated struct ListDataPointsResponseDTO: Decodable, Sendable {
    let dataPoints: [DataPointDTO]?
    let nextPageToken: String?
}

nonisolated struct DataPointDTO: Decodable, Sendable {
    nonisolated struct DailyRestingHeartRate: Decodable, Sendable {
        let date: APIDate
        let beatsPerMinute: FlexibleInt?
    }
    nonisolated struct DailyHeartRateVariability: Decodable, Sendable {
        let date: APIDate
        let averageHeartRateVariabilityMilliseconds: Double?
    }
    nonisolated struct DailyVO2Max: Decodable, Sendable {
        let date: APIDate
        let vo2Max: Double?
    }
    nonisolated struct DailyRespiratoryRate: Decodable, Sendable {
        let date: APIDate
        let breathsPerMinute: Double?
    }

    let name: String?
    let sleep: SleepDTO?
    let dailyRestingHeartRate: DailyRestingHeartRate?
    let dailyHeartRateVariability: DailyHeartRateVariability?
    let dailyVo2Max: DailyVO2Max?
    let dailyRespiratoryRate: DailyRespiratoryRate?
}

nonisolated struct SleepDTO: Decodable, Sendable {
    nonisolated struct Interval: Decodable, Sendable {
        let startTime: String
        let endTime: String
        let startUtcOffset: String?
        let endUtcOffset: String?
        let civilEndTime: APICivilDateTime?
    }
    nonisolated struct Metadata: Decodable, Sendable {
        let mainSleep: Bool?
        let nap: Bool?
        let processed: Bool?
    }
    nonisolated struct StageSummary: Decodable, Sendable {
        let type: String?
        let minutes: FlexibleInt?
    }
    nonisolated struct Summary: Decodable, Sendable {
        let minutesAsleep: FlexibleInt?
        let minutesInSleepPeriod: FlexibleInt?
        let minutesAwake: FlexibleInt?
        let stagesSummary: [StageSummary]?
    }

    let interval: Interval
    /// "CLASSIC" (asleep / restless / awake) or "STAGES" (light / deep / REM / awake).
    let type: String?
    let metadata: Metadata?
    let summary: Summary?
}

// MARK: - Profile, settings, devices

nonisolated struct HealthProfileDTO: Decodable, Sendable {
    let age: Int?
}

nonisolated struct HealthSettingsDTO: Decodable, Sendable {
    let timeZone: String?
    let distanceUnit: String?
}

nonisolated struct PairedDevicesResponseDTO: Decodable, Sendable {
    let pairedDevices: [PairedDeviceDTO]?
    let nextPageToken: String?
}

nonisolated struct PairedDeviceDTO: Decodable, Equatable, Sendable {
    let name: String?
    /// The product name, e.g. "Fitbit Air".
    let deviceVersion: String?
    /// TRACKER or SCALE.
    let deviceType: String?
    let batteryLevel: Int?
    let batteryStatus: String?
    let lastSyncTime: String?

    var lastSync: Date? { lastSyncTime.flatMap(GoogleTime.date(from:)) }
}

// MARK: - Time formats

nonisolated enum GoogleTime {
    /// Parses RFC 3339 timestamps, with or without fractional seconds.
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Parses a protobuf Duration like "-14400s" or "3600.5s" into whole seconds.
    static func seconds(fromDuration string: String) -> Int? {
        guard string.hasSuffix("s"), let value = Double(string.dropLast()) else { return nil }
        return Int(value.rounded())
    }
}
