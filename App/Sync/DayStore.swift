import Foundation

/// Everything the phone keeps between launches. Raw-ish health data stays here,
/// on the device; only daily summaries are uploaded.
nonisolated struct LocalState: Codable, Equatable, Sendable {
    /// One record per day with data, oldest first.
    var records: [DayRecord] = []
    var goals = Goals()
    /// The newest date fetched from Google Health, so the next sync can fill any gap.
    var fetchedThrough: CivilDate?
    var lastSyncAt: Date?
    var device: DeviceStatus?
    /// Health categories the user didn't grant on Google's consent screen.
    var missingCategories: Set<HealthCategory> = []
    /// What Supabase already has, as "date/metric" → fingerprint, so unchanged rows aren't re-sent.
    var uploaded: [String: String] = [:]
    /// The Supabase user these records belong to; a different account starts fresh.
    var accountID: String?
    /// Age from the Google Health profile, refreshed each sync (for biological age).
    var profileAge: Int?
    /// An age the user typed in, which wins over the profile age.
    var ageOverride: Int?
    /// Sex for the fitness norms behind biological age; nil uses the average of both.
    var sex: BiologicalSex?

    /// Replaces every record in `range` with `fresh` (days without data drop out).
    mutating func replaceRecords(in range: ClosedRange<CivilDate>, with fresh: [DayRecord]) {
        records.removeAll { range.contains($0.date) }
        records += fresh.filter { range.contains($0.date) }
        records.sort { $0.date < $1.date }
    }
}

/// Saves `LocalState` as one JSON file. An actor, so reads and writes never overlap.
/// The file lives in the App Group container when available (shared with the widget).
actor DayStore {
    private let fileURL: URL
    private var cached: LocalState?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The app's real store.
    static func standard(appGroup: String? = AppGroup.identifier) -> DayStore {
        DayStore(fileURL: SharedFiles.directory(appGroup: appGroup).appendingPathComponent("health-days.json"))
    }

    func load() -> LocalState {
        if let cached { return cached }
        let state = (try? Data(contentsOf: fileURL)).flatMap { try? Self.decoder.decode(LocalState.self, from: $0) }
            ?? LocalState()
        cached = state
        return state
    }

    /// Changes the state and saves it. Returns the new state.
    @discardableResult
    func update(_ change: @Sendable (inout LocalState) -> Void) throws -> LocalState {
        var state = load()
        change(&state)
        try save(state)
        return state
    }

    /// Forgets everything (sign-out, account deletion, or a different account).
    func reset() throws {
        try save(LocalState())
    }

    private func save(_ state: LocalState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
        cached = state
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
