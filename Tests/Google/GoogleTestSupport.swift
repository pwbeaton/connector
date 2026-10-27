import Foundation
@testable import App

/// Answers HTTP requests from a handler and records what was sent. The handler is
/// `@Sendable` because the client calls it from its own actor, not the test's main actor.
nonisolated final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (_ request: URLRequest, _ earlier: [URLRequest]) -> (Int, String)

    private let lock = NSLock()
    private let handler: Handler
    private var sent: [URLRequest] = []

    /// `earlier` holds the requests sent before this one, for answers that change over time.
    init(withHistory handler: @escaping Handler) {
        self.handler = handler
    }

    convenience init(_ handler: @escaping @Sendable (URLRequest) -> (Int, String)) {
        self.init(withHistory: { request, _ in handler(request) })
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            defer { sent.append(request) }
            return handler(request, sent)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

nonisolated final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: GoogleTokens?

    init(_ tokens: GoogleTokens? = nil) { self.tokens = tokens }

    func load() -> GoogleTokens? { lock.withLock { tokens } }
    func save(_ tokens: GoogleTokens) throws { lock.withLock { self.tokens = tokens } }
    func delete() { lock.withLock { tokens = nil } }
}

let testConfig = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com",
                                   redirectScheme: "com.googleusercontent.apps.1234-abc")

/// A fixed "now" for token-expiry tests. Nonisolated so `@Sendable` clock closures can read it.
nonisolated enum TestClock {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
}

func validTokens(expiresIn seconds: TimeInterval = 3600, refresh: String? = "refresh-1") -> GoogleTokens {
    GoogleTokens(accessToken: "access-1", expiresAt: TestClock.now.addingTimeInterval(seconds), refreshToken: refresh,
                 grantedScopes: Set(GoogleScopes.all), idToken: "id-token")
}

nonisolated extension URLRequest {
    var bodyString: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    func queryValue(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// Responses shaped exactly like the Google Health API v4 description.
nonisolated enum Fixtures {
    static let rollUp = """
    {
      "rollupDataPoints": [
        {
          "civilStartTime": {"date": {"year": 2026, "month": 10, "day": 26}},
          "civilEndTime": {"date": {"year": 2026, "month": 10, "day": 27}},
          "steps": {"countSum": "10432"},
          "distance": {"millimetersSum": "7934000"},
          "activeZoneMinutes": {"sumInFatBurnHeartZone": "12", "sumInCardioHeartZone": "20", "sumInPeakHeartZone": "4"}
        },
        {
          "civilStartTime": {"date": {"year": 2026, "month": 10, "day": 27}},
          "civilEndTime": {"date": {"year": 2026, "month": 10, "day": 28}},
          "steps": {"countSum": "0"}
        }
      ]
    }
    """

    static let dailyValues = """
    {
      "dataPoints": [
        {"name": "users/me/dataTypes/daily-heart-rate-variability/dataPoints/a",
         "dailyHeartRateVariability": {"date": {"year": 2026, "month": 10, "day": 27},
                                       "averageHeartRateVariabilityMilliseconds": 54.25,
                                       "entropy": 3.1}},
        {"dailyRestingHeartRate": {"date": {"year": 2026, "month": 10, "day": 27}, "beatsPerMinute": "57",
                                   "dailyRestingHeartRateMetadata": {"calculationMethod": "WITH_SLEEP"}}},
        {"dailyVo2Max": {"date": {"year": 2026, "month": 10, "day": 27}, "vo2Max": 46.2, "cardioFitnessLevel": "GOOD"}},
        {"dailyRespiratoryRate": {"date": {"year": 2026, "month": 10, "day": 27}, "breathsPerMinute": 14.8}}
      ]
    }
    """

    /// One staged main sleep ending 2026-10-27 06:41 EDT, plus a nap that afternoon.
    static let sleep = """
    {
      "dataPoints": [
        {
          "sleep": {
            "interval": {
              "startTime": "2026-10-27T03:02:00Z", "endTime": "2026-10-27T10:41:00.500Z",
              "startUtcOffset": "-14400s", "endUtcOffset": "-14400s",
              "civilStartTime": {"date": {"year": 2026, "month": 10, "day": 26}, "time": {"hours": 23, "minutes": 2}},
              "civilEndTime": {"date": {"year": 2026, "month": 10, "day": 27}, "time": {"hours": 6, "minutes": 41}}
            },
            "type": "STAGES",
            "metadata": {"mainSleep": true, "nap": false, "processed": true, "stagesStatus": "SUCCEEDED"},
            "summary": {
              "minutesAsleep": "421", "minutesAwake": "38", "minutesInSleepPeriod": "459",
              "stagesSummary": [
                {"type": "LIGHT", "minutes": "230", "count": "20"},
                {"type": "DEEP", "minutes": "78", "count": "4"},
                {"type": "REM", "minutes": "113", "count": "6"},
                {"type": "AWAKE", "minutes": "38", "count": "18"}
              ]
            }
          }
        },
        {
          "sleep": {
            "interval": {
              "startTime": "2026-10-27T18:10:00Z", "endTime": "2026-10-27T18:40:00Z",
              "startUtcOffset": "-14400s", "endUtcOffset": "-14400s",
              "civilEndTime": {"date": {"year": 2026, "month": 10, "day": 27}}
            },
            "type": "CLASSIC",
            "metadata": {"mainSleep": false, "nap": true},
            "summary": {"minutesAsleep": "27", "minutesInSleepPeriod": "30",
                        "stagesSummary": [{"type": "ASLEEP", "minutes": "27"}, {"type": "AWAKE", "minutes": "3"}]}
          }
        }
      ],
      "nextPageToken": ""
    }
    """

    static let pairedDevices = """
    {"pairedDevices": [{"name": "users/me/pairedDevices/9", "deviceVersion": "Fitbit Air", "deviceType": "TRACKER",
                        "batteryLevel": 80, "batteryStatus": "High", "lastSyncTime": "2026-10-27T10:55:00Z",
                        "features": ["SLEEP", "HEART_RATE"]}]}
    """

    static let tokenResponse = """
    {"access_token": "access-new", "expires_in": 3599, "refresh_token": "refresh-new",
     "scope": "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/googlehealth.sleep.readonly",
     "token_type": "Bearer", "id_token": "header.payload.signature"}
    """
}
