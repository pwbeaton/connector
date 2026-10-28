import Foundation

/// Groups of Google Health data the user can grant or withhold on the consent screen.
nonisolated enum HealthCategory: String, Codable, Sendable, CaseIterable, Comparable {
    case activity, sleep, heart

    var title: String {
        switch self {
        case .activity: "Activity (steps, Active Zone Minutes)"
        case .sleep: "Sleep"
        case .heart: "Heart (HRV, resting heart rate)"
        }
    }

    static func < (lhs: HealthCategory, rhs: HealthCategory) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// The tracker as Google Health reports it ("Fitbit Air · battery 80% · synced 4 min ago").
nonisolated struct DeviceStatus: Codable, Equatable, Sendable {
    var name: String
    var batteryPercent: Int?
    var lastSync: Date?

    /// Picks the tracker from the paired devices, preferring a Fitbit Air.
    init?(devices: [PairedDeviceDTO]) {
        let trackers = devices.filter { $0.deviceType == nil || $0.deviceType == "TRACKER" }
        guard let device = trackers.first(where: { $0.deviceVersion?.localizedCaseInsensitiveContains("Air") == true })
            ?? trackers.first
        else { return nil }
        self.init(name: device.deviceVersion ?? device.name ?? "Fitbit", batteryPercent: device.batteryLevel,
                  lastSync: device.lastSync)
    }

    init(name: String, batteryPercent: Int?, lastSync: Date?) {
        self.name = name
        self.batteryPercent = batteryPercent
        self.lastSync = lastSync
    }
}

/// One fetch of health data: a record for every day that has any, plus what was off-limits.
nonisolated struct HealthFetchResult: Sendable {
    var records: [DayRecord]
    var missing: Set<HealthCategory>
}

/// Where health data comes from. The real one calls Google Health; tests use a fake.
nonisolated protocol HealthDataSource: Sendable {
    /// Day records for every civil date in `start...end`.
    func fetch(from start: CivilDate, through end: CivilDate) async throws -> HealthFetchResult
    /// The paired tracker, or nil if none (or the settings scope wasn't granted).
    func device() async throws -> DeviceStatus?
    /// The user's age in years from their Google Health profile (for biological age).
    func profileAge() async throws -> Int?
}

nonisolated extension HealthDataSource {
    func profileAge() async throws -> Int? { nil }
}

/// Reads the Fitbit Air's data from the Google Health API (about 8 calls per sync).
nonisolated struct GoogleHealthSource: HealthDataSource {
    let client: GoogleHealthClient

    static let rollUpTypes = ["steps", "distance", "active-zone-minutes"]
    static let heartTypes = ["daily-heart-rate-variability", "daily-resting-heart-rate"]
    /// Shown in Trends only; missing them never blocks anything.
    static let extraTypes = ["daily-vo2-max", "daily-respiratory-rate"]

    func fetch(from start: CivilDate, through end: CivilDate) async throws -> HealthFetchResult {
        let granted = await client.session.currentTokens?.grantedScopes
        var fetch = HealthFetch()
        var missing = Set<HealthCategory>()

        // Daily totals. dailyRollUp takes at most 90 days, end date exclusive.
        if granted.map({ $0.contains(GoogleScopes.activity) }) ?? true {
            do {
                for type in Self.rollUpTypes {
                    var chunkStart = start
                    while chunkStart <= end {
                        let chunkEnd = min(chunkStart.adding(days: 89), end)
                        let points = try await client.dailyRollUp(type, from: chunkStart, to: chunkEnd.adding(days: 1))
                        GoogleHealthMapper.addRollups(points, to: &fetch)
                        chunkStart = chunkEnd.adding(days: 1)
                    }
                }
            } catch GoogleHealthError.missingScope {
                missing.insert(.activity)
            }
        } else {
            missing.insert(.activity)
        }

        // Nightly HRV and resting heart rate.
        if granted.map({ $0.contains(GoogleScopes.healthMetrics) }) ?? true {
            do {
                for type in Self.heartTypes {
                    let points = try await client.list(type, filter: GoogleHealthClient.dailyFilter(type, from: start),
                                                       pageSize: 1000)
                    GoogleHealthMapper.addDailyValues(points, to: &fetch)
                }
            } catch GoogleHealthError.missingScope {
                missing.insert(.heart)
            }
        } else {
            missing.insert(.heart)
        }

        // VO2 max and breathing rate: nice to have, so any failure is ignored.
        for type in Self.extraTypes {
            if let points = try? await client.list(type, filter: GoogleHealthClient.dailyFilter(type, from: start),
                                                   pageSize: 1000) {
                GoogleHealthMapper.addDailyValues(points, to: &fetch)
            }
        }

        // Sleep sessions (at most 25 per page). Nights belong to the date you woke up.
        if granted.map({ $0.contains(GoogleScopes.sleep) }) ?? true {
            do {
                let points = try await client.list("sleep", filter: GoogleHealthClient.sleepFilter(from: start), pageSize: 25)
                GoogleHealthMapper.addDailyValues(points, to: &fetch)
            } catch GoogleHealthError.missingScope {
                missing.insert(.sleep)
            }
        } else {
            missing.insert(.sleep)
        }

        return HealthFetchResult(records: GoogleHealthMapper.records(from: fetch, dates: start.through(end)),
                                 missing: missing)
    }

    func device() async throws -> DeviceStatus? {
        do {
            return DeviceStatus(devices: try await client.pairedDevices())
        } catch GoogleHealthError.missingScope {
            return nil
        }
    }

    func profileAge() async throws -> Int? {
        do {
            return try await client.profile().age
        } catch GoogleHealthError.missingScope {
            return nil
        }
    }
}
