import Foundation

nonisolated enum GoogleHealthError: Error, Equatable {
    /// The user unticked the scope this data needs on Google's consent screen.
    case missingScope
    /// The Google account has no Google Health (Fitbit) profile. Usually the user
    /// signed in with a different Google account from the one their tracker uses.
    case accountNotLinked
    case http(status: Int, message: String)
    case invalidResponse

    static let accountNotLinkedMessage =
        "This Google account isn't linked to Google Health. Sign out and sign in with the Google account your Fitbit Air uses."
}

/// Calls the Google Health API v4 for the signed-in user ("users/me").
/// Adds the access token, follows pages, refreshes the token once on 401, and
/// retries rate limits and server errors with backoff.
nonisolated struct GoogleHealthClient: Sendable {
    static let baseURL = "https://health.googleapis.com/v4/users/me/"

    let session: GoogleSession
    var transport: any HTTPTransport = URLSessionTransport()
    /// Waits before retry number `attempt` (1, 2, 3…). Tests replace it with no wait.
    var retryDelay: @Sendable (Int) async -> Void = { attempt in
        try? await Task.sleep(for: .seconds(1 << attempt))
    }
    var maxRetries = 3

    // MARK: Data

    /// Daily totals (steps, distance, active-zone-minutes) for civil dates in [start, end).
    /// The API allows at most 90 days per call.
    func dailyRollUp(_ dataType: String, from start: CivilDate, to end: CivilDate) async throws -> [DailyRollupDataPointDTO] {
        var results: [DailyRollupDataPointDTO] = []
        var pageToken: String?
        repeat {
            let body = DailyRollUpRequestDTO(
                range: .init(start: APICivilDateTime(date: APIDate(start)), end: APICivilDateTime(date: APIDate(end))),
                windowSizeDays: 1, pageSize: 100, pageToken: pageToken)
            let response: DailyRollUpResponseDTO = try await send(path: "dataTypes/\(dataType)/dataPoints:dailyRollUp",
                                                                 method: "POST", body: try JSONEncoder().encode(body))
            results += response.rollupDataPoints ?? []
            pageToken = response.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return results
    }

    /// Data points of one type matching `filter`, following every page.
    func list(_ dataType: String, filter: String?, pageSize: Int) async throws -> [DataPointDTO] {
        var results: [DataPointDTO] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "pageSize", value: String(pageSize))]
            if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let response: ListDataPointsResponseDTO = try await send(path: "dataTypes/\(dataType)/dataPoints", query: query)
            results += response.dataPoints ?? []
            pageToken = response.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return results
    }

    func profile() async throws -> HealthProfileDTO {
        try await send(path: "profile")
    }

    func settings() async throws -> HealthSettingsDTO {
        try await send(path: "settings")
    }

    func pairedDevices() async throws -> [PairedDeviceDTO] {
        let response: PairedDevicesResponseDTO = try await send(path: "pairedDevices")
        return response.pairedDevices ?? []
    }

    // MARK: Filters (syntax from the API description; dates are the user's civil dates)

    static func dailyFilter(_ dataType: String, from start: CivilDate) -> String {
        "\(dataType.replacingOccurrences(of: "-", with: "_")).date >= \"\(start)\""
    }

    static func sleepFilter(from start: CivilDate) -> String {
        "sleep.interval.civil_end_time >= \"\(start)\""
    }

    // MARK: Transport

    /// Google answers FAILED_PRECONDITION with reason ACCOUNT_NOT_LINKED when the
    /// account has no Google Health profile.
    static func isAccountNotLinked(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).contains("ACCOUNT_NOT_LINKED")
    }

    func makeRequest(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                     accessToken: String) -> URLRequest {
        var components = URLComponents(string: Self.baseURL + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send<T: Decodable>(path: String, method: String = "GET", query: [URLQueryItem] = [],
                                    body: Data? = nil) async throws -> T {
        var attempt = 0
        var refreshedAfter401 = false
        while true {
            let token = try await session.accessToken()
            let request = makeRequest(path: path, method: method, query: query, body: body, accessToken: token)
            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw GoogleHealthError.invalidResponse
                }
            case 400 where Self.isAccountNotLinked(data), 403 where Self.isAccountNotLinked(data):
                throw GoogleHealthError.accountNotLinked
            case 401 where !refreshedAfter401:
                refreshedAfter401 = true
                _ = try await session.accessToken(forceRefresh: true)
            case 403 where String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("scope"):
                throw GoogleHealthError.missingScope
            case 429 where attempt < maxRetries, 500..<600 where attempt < maxRetries:
                attempt += 1
                await retryDelay(attempt)
            default:
                throw GoogleHealthError.http(status: response.statusCode,
                                             message: String(decoding: data.prefix(300), as: UTF8.self))
            }
        }
    }
}
