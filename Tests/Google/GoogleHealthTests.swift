import Foundation
import Testing
@testable import App

struct GoogleDecodingTests {
    @Test func flexibleIntAcceptsStringsAndNumbers() throws {
        let values = try JSONDecoder().decode([FlexibleInt].self, from: Data(#"["8423", 12, 3.6]"#.utf8))
        #expect(values.map(\.value) == [8423, 12, 4])
    }

    @Test func parsesGoogleTimestampsAndDurations() {
        #expect(GoogleTime.date(from: "2026-10-27T10:41:00Z") == Date(timeIntervalSince1970: 1_793_097_660))
        #expect(GoogleTime.date(from: "2026-10-27T10:41:00.500Z") != nil)
        #expect(GoogleTime.seconds(fromDuration: "-14400s") == -14400)
        #expect(GoogleTime.seconds(fromDuration: "3600.4s") == 3600)
        #expect(GoogleTime.seconds(fromDuration: "garbage") == nil)
    }

    @Test func decodesRollUps() throws {
        let response = try JSONDecoder().decode(DailyRollUpResponseDTO.self, from: Data(Fixtures.rollUp.utf8))
        #expect(response.rollupDataPoints?.count == 2)
        #expect(response.rollupDataPoints?.first?.steps?.countSum?.value == 10432)
    }

    @Test func decodesPairedDevices() throws {
        let response = try JSONDecoder().decode(PairedDevicesResponseDTO.self, from: Data(Fixtures.pairedDevices.utf8))
        let device = try #require(response.pairedDevices?.first)
        #expect(device.deviceVersion == "Fitbit Air")
        #expect(device.batteryLevel == 80)
        #expect(device.lastSync != nil)
    }
}

struct GoogleHealthMapperTests {
    private let oct26 = CivilDate(year: 2026, month: 10, day: 26)
    private let oct27 = CivilDate(year: 2026, month: 10, day: 27)

    private func fetch() throws -> HealthFetch {
        var fetch = HealthFetch()
        let rollUp = try JSONDecoder().decode(DailyRollUpResponseDTO.self, from: Data(Fixtures.rollUp.utf8))
        GoogleHealthMapper.addRollups(rollUp.rollupDataPoints ?? [], to: &fetch)
        let daily = try JSONDecoder().decode(ListDataPointsResponseDTO.self, from: Data(Fixtures.dailyValues.utf8))
        GoogleHealthMapper.addDailyValues(daily.dataPoints ?? [], to: &fetch)
        let sleep = try JSONDecoder().decode(ListDataPointsResponseDTO.self, from: Data(Fixtures.sleep.utf8))
        GoogleHealthMapper.addDailyValues(sleep.dataPoints ?? [], to: &fetch)
        return fetch
    }

    @Test func rollUpsBecomeDailyTotals() throws {
        let fetch = try fetch()
        #expect(fetch.steps[oct26] == 10432)
        #expect(fetch.distanceMeters[oct26] == 7934)
        #expect(fetch.activeZoneMinutes[oct26] == 36)
        // "0" is a real zero (tracker worn, no steps yet), not missing data.
        #expect(fetch.steps[oct27] == 0)
    }

    @Test func dailyValuesAreKeyedByTheirDate() throws {
        let fetch = try fetch()
        #expect(fetch.hrvMs[oct27] == 54.25)
        #expect(fetch.restingHeartRate[oct27] == 57)
        #expect(fetch.vo2Max[oct27] == 46.2)
        #expect(fetch.respiratoryRate[oct27] == 14.8)
    }

    @Test func mainSleepBecomesLastNight() throws {
        let record = try #require(GoogleHealthMapper.records(from: try fetch(), dates: [oct27]).first)
        let sleep = try #require(record.sleep)
        #expect(sleep.minutesAsleep == 421)
        #expect(sleep.minutesInBed == 459)
        #expect(sleep.deepMinutes == 78)
        #expect(sleep.remMinutes == 113)
        #expect(sleep.lightMinutes == 230)
        #expect(sleep.endUTCOffsetSeconds == -14400)
        #expect(sleep.wakeMinuteOfDay == 6 * 60 + 41)
        #expect(record.napMinutes == 27)
    }

    @Test func classicSleepHasNoStages() throws {
        let nap = try JSONDecoder().decode(ListDataPointsResponseDTO.self, from: Data(Fixtures.sleep.utf8))
            .dataPoints?.last?.sleep
        let napDTO = try #require(nap)
        let night = try #require(GoogleHealthMapper.night(from: napDTO))
        #expect(night.isNap)
        #expect(night.summary.hasStages == false)
        #expect(night.summary.deepMinutes == nil)
    }

    @Test func daysWithoutDataAreLeftOut() throws {
        let records = GoogleHealthMapper.records(from: try fetch(), dates: [oct26, oct27, oct27.adding(days: 1)])
        #expect(records.map(\.date) == [oct26, oct27])
    }
}

struct GoogleHealthClientTests {
    private func client(_ transport: StubTransport, tokens: GoogleTokens = validTokens()) -> GoogleHealthClient {
        let session = GoogleSession(config: testConfig, store: InMemoryTokenStore(tokens), transport: transport,
                                    now: { TestClock.now })
        return GoogleHealthClient(session: session, transport: transport, retryDelay: { _ in })
    }

    @Test func dailyRollUpPostsACivilDateRange() async throws {
        let transport = StubTransport { _ in (200, Fixtures.rollUp) }
        let points = try await client(transport).dailyRollUp("steps", from: CivilDate(year: 2026, month: 7, day: 30),
                                                              to: CivilDate(year: 2026, month: 10, day: 28))
        #expect(points.count == 2)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://health.googleapis.com/v4/users/me/dataTypes/steps/dataPoints:dailyRollUp")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        let range = body?["range"] as? [String: Any]
        let start = (range?["start"] as? [String: Any])?["date"] as? [String: Int]
        #expect(start == ["year": 2026, "month": 7, "day": 30])
        #expect(body?["windowSizeDays"] as? Int == 1)
    }

    @Test func listFollowsEveryPage() async throws {
        let transport = StubTransport { request in
            if request.queryValue("pageToken") == nil {
                return (200, #"{"dataPoints": [{"dailyRestingHeartRate": {"date": {"year": 2026, "month": 10, "day": 26}, "beatsPerMinute": "55"}}], "nextPageToken": "p2"}"#)
            }
            return (200, Fixtures.dailyValues)
        }
        let filter = GoogleHealthClient.dailyFilter("daily-resting-heart-rate", from: CivilDate(year: 2026, month: 10, day: 1))
        let points = try await client(transport).list("daily-resting-heart-rate", filter: filter, pageSize: 1000)
        #expect(points.count == 5)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.first?.queryValue("filter") == #"daily_resting_heart_rate.date >= "2026-10-01""#)
        #expect(transport.requests.last?.queryValue("pageToken") == "p2")
    }

    @Test func refreshesOnceAfterA401() async throws {
        let transport = StubTransport(withHistory: { request, earlier in
            if request.url == GoogleOAuthEndpoints.token {
                return (200, #"{"access_token": "access-2", "expires_in": 3600}"#)
            }
            let earlierAPICalls = earlier.filter { $0.url != GoogleOAuthEndpoints.token }.count
            return earlierAPICalls == 0 ? (401, "") : (200, Fixtures.pairedDevices)
        })
        let devices = try await client(transport).pairedDevices()
        #expect(devices.first?.deviceVersion == "Fitbit Air")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test func retriesRateLimitsThenSucceeds() async throws {
        let transport = StubTransport(withHistory: { _, earlier in
            earlier.count < 2 ? (429, "slow down") : (200, Fixtures.pairedDevices)
        })
        let devices = try await client(transport).pairedDevices()
        #expect(devices.count == 1)
        #expect(transport.requests.count == 3)
    }

    @Test func givesUpAfterThreeRetries() async {
        let transport = StubTransport { _ in (503, "unavailable") }
        await #expect(throws: GoogleHealthError.self) { try await client(transport).pairedDevices() }
        #expect(transport.requests.count == 4)
    }

    @Test func reportsAMissingScope() async {
        let transport = StubTransport { _ in (403, #"{"error": {"message": "Request had insufficient authentication scopes."}}"#) }
        await #expect(throws: GoogleHealthError.missingScope) { try await client(transport).settings() }
    }

    @Test func sleepFilterUsesTheCivilEndTime() {
        #expect(GoogleHealthClient.sleepFilter(from: CivilDate(year: 2026, month: 10, day: 1))
                == #"sleep.interval.civil_end_time >= "2026-10-01""#)
    }
}
