import Foundation

/// The tracker in demo mode: serves `DemoData` as if it came from Google Health.
nonisolated struct DemoHealthSource: HealthDataSource {
    let today: CivilDate

    func fetch(from start: CivilDate, through end: CivilDate) async throws -> HealthFetchResult {
        let days = max(1, start.days(until: today) + 1)
        let records = DemoData.records(endingOn: today, days: days).filter { $0.date >= start && $0.date <= end }
        return HealthFetchResult(records: records, missing: [])
    }

    func device() async throws -> DeviceStatus? {
        DeviceStatus(name: "Fitbit Air", batteryPercent: 82, lastSync: Date().addingTimeInterval(-4 * 60))
    }

    func profileAge() async throws -> Int? { 29 }
}

/// A pretend server with four friends in one group, for demo mode, previews, and
/// screenshots. Everything stays in memory; nothing leaves the phone.
actor DemoBackend: Backend {
    static let you = UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!
    static let camp = GroupInfo(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!, name: "Training Camp",
                                inviteCode: "CAMP2345", createdBy: friends[0].id)

    nonisolated struct Friend: Sendable {
        let id: UUID
        let name: String
        let profile: DemoData.Profile
        let shares: Set<SharingCategory>
    }

    /// Made-up people. Sam keeps Recovery private, so cards show what "not shared" looks like.
    static let friends: [Friend] = [
        Friend(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "Maya",
               profile: .init(sleepMinutes: 470, wakeMinute: 6 * 60 + 15, hrv: 72, restingHR: 52, steps: 11_200,
                              intensity: 12, vo2Max: 49, phase: 17),
               shares: Set(SharingCategory.allCases)),
        Friend(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "Leo",
               profile: .init(sleepMinutes: 405, wakeMinute: 7 * 60 + 10, hrv: 45, restingHR: 60, steps: 7_400,
                              intensity: 2, vo2Max: 41, phase: 41),
               shares: Set(SharingCategory.allCases)),
        Friend(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "Priya",
               profile: .init(sleepMinutes: 455, wakeMinute: 6 * 60, hrv: 64, restingHR: 54, steps: 9_800,
                              intensity: 9, vo2Max: 47, phase: 63),
               shares: Set(SharingCategory.allCases)),
        Friend(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, name: "Sam",
               profile: .init(sleepMinutes: 420, wakeMinute: 7 * 60 + 30, hrv: 52, restingHR: 58, steps: 6_400,
                              intensity: 4, vo2Max: 43, phase: 88),
               shares: [.sleep, .activity]),
    ]

    private let today: CivilDate
    private var signedIn: Bool
    private var groups: [GroupInfo]
    private var memberIDs: [UUID: [UUID]]
    private var profiles: [UUID: Profile]
    private var goals = Goals()
    /// Everyone's daily rows, keyed by "user/date/metric".
    private var metrics: [String: FriendMetric] = [:]
    private var sharingSettings: [SharingSetting] = []
    private var reactionList: [Reaction] = []

    /// - Parameter inGroup: false starts with no group (to show onboarding's group step).
    init(today: CivilDate, signedIn: Bool = true, inGroup: Bool = true) {
        self.today = today
        self.signedIn = signedIn
        groups = inGroup ? [Self.camp] : []
        memberIDs = [Self.camp.id: [Self.you] + Self.friends.map(\.id)]
        var profiles = [Self.you: Profile(id: Self.you, displayName: "You", timezone: "America/New_York",
                                          deviceName: "Fitbit Air")]
        for friend in Self.friends {
            profiles[friend.id] = Profile(id: friend.id, displayName: friend.name, timezone: "America/New_York",
                                          deviceName: "Fitbit Air")
        }
        self.profiles = profiles
        if inGroup {
            sharingSettings = SharingSetting.shareAll(userID: Self.you, groupID: Self.camp.id)
        }

        for friend in Self.friends {
            let records = DemoData.records(endingOn: today, days: 35, profile: friend.profile)
            let rows = MetricRows.rows(records: records, scores: DailyScoring.score(records, goals: Goals()))
            for row in rows where friend.shares.contains(row.metric.category) && row.date > today.adding(days: -14) {
                let metric = FriendMetric(userID: friend.id, date: row.date, metric: row.metric, value: row.value,
                                          detail: row.detail.mapValues(Double.init))
                metrics["\(friend.id)/\(row.key)"] = metric
            }
        }
        // A few fist bumps from friends on your morning.
        reactionList = [
            Reaction(id: UUID(), groupID: Self.camp.id, authorID: Self.friends[0].id, ownerID: Self.you, day: today, emoji: "👊"),
            Reaction(id: UUID(), groupID: Self.camp.id, authorID: Self.friends[2].id, ownerID: Self.you, day: today, emoji: "👊"),
            Reaction(id: UUID(), groupID: Self.camp.id, authorID: Self.you, ownerID: Self.friends[0].id, day: today, emoji: "🔥"),
        ]
    }

    // MARK: Account

    func signIn(googleIDToken: String, accessToken: String?, rawNonce: String) async throws -> UUID {
        signedIn = true
        return Self.you
    }

    func currentUserID() async -> UUID? { signedIn ? Self.you : nil }
    func accountID() async -> String? { signedIn ? "demo" : nil }
    func signOut() async { signedIn = false }
    func deleteAccount() async throws { signedIn = false }

    // MARK: Profile and goals

    func myProfile() async throws -> Profile { profiles[Self.you]! }

    func updateProfile(_ update: ProfileUpdate) async throws {
        if let name = update.displayName { profiles[Self.you]?.displayName = name }
    }

    func myGoals() async throws -> Goals { goals }
    func updateGoals(_ goals: Goals) async throws { self.goals = goals }

    // MARK: Groups

    func myGroups() async throws -> [GroupInfo] { groups }

    func members(of groupID: UUID) async throws -> [Member] {
        (memberIDs[groupID] ?? []).compactMap { id in
            profiles[id].map { Member(profile: $0, isOwner: id == groups.first { $0.id == groupID }?.createdBy) }
        }
    }

    func createGroup(named name: String) async throws -> GroupInfo {
        let group = GroupInfo(id: UUID(), name: name.trimmingCharacters(in: .whitespaces), inviteCode: "TEAM4567",
                              createdBy: Self.you)
        groups.append(group)
        memberIDs[group.id] = [Self.you]
        return group
    }

    func joinGroup(code: String) async throws -> GroupInfo {
        guard InviteCode.normalize(code) == Self.camp.inviteCode else { throw BackendError.unknownInviteCode }
        if !groups.contains(Self.camp) { groups.append(Self.camp) }
        return Self.camp
    }

    func previewGroup(code: String) async throws -> GroupPreview? {
        guard InviteCode.normalize(code) == Self.camp.inviteCode else { return nil }
        let people = Self.friends.map { GroupPreview.Person(displayName: $0.name, avatarURL: nil) }
        return GroupPreview(name: Self.camp.name, members: people)
    }

    func leaveGroup(_ groupID: UUID) async throws {
        groups.removeAll { $0.id == groupID }
        sharingSettings.removeAll { $0.groupID == groupID }
    }

    // MARK: Sharing

    func sharing(in groupID: UUID) async throws -> [SharingSetting] {
        sharingSettings.filter { $0.groupID == groupID }
    }

    func saveSharing(_ settings: [SharingSetting]) async throws {
        for setting in settings {
            sharingSettings.removeAll { $0.groupID == setting.groupID && $0.category == setting.category }
            sharingSettings.append(setting)
        }
    }

    // MARK: Friends' numbers

    func upsertMetrics(_ rows: [MetricRow]) async throws {
        for row in rows where row.date > today.adding(days: -14) {
            metrics["\(Self.you)/\(row.key)"] = FriendMetric(userID: Self.you, date: row.date, metric: row.metric,
                                                             value: row.value, detail: row.detail.mapValues(Double.init))
        }
    }

    func feed(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [FriendMetric] {
        let members = Set(memberIDs[groupID] ?? [])
        return metrics.values
            .filter { members.contains($0.userID) && $0.date >= start && $0.date <= end && isShared($0) }
            .sorted { ($0.date, $0.userID.uuidString, $0.metric.rawValue) < ($1.date, $1.userID.uuidString, $1.metric.rawValue) }
    }

    func leaderboard(groupID: UUID, weekStart: CivilDate, metric: LeaderboardMetric) async throws -> [LeaderboardEntry] {
        let rows = try await feed(groupID: groupID, from: weekStart, through: weekStart.adding(days: 6))
        return Leaderboards.rank(rows, metric: metric) { profiles[$0]?.displayName ?? "" }
    }

    private func isShared(_ row: FriendMetric) -> Bool {
        guard row.userID == Self.you else { return true }
        return sharingSettings.contains {
            $0.category == row.metric.category && $0.enabled && !$0.hiddenDates.contains(row.date)
        }
    }

    // MARK: Reactions

    func reactions(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [Reaction] {
        reactionList.filter { $0.groupID == groupID && $0.day >= start && $0.day <= end }
    }

    func addReaction(groupID: UUID, ownerID: UUID, day: CivilDate, emoji: String) async throws -> Reaction {
        let reaction = Reaction(id: UUID(), groupID: groupID, authorID: Self.you, ownerID: ownerID, day: day, emoji: emoji)
        reactionList.append(reaction)
        return reaction
    }

    func removeReaction(id: UUID) async throws {
        reactionList.removeAll { $0.id == id }
    }
}

/// Weekly leaderboards computed the same way as the server's weekly_leaderboard().
nonisolated enum Leaderboards {
    static func rank(_ rows: [FriendMetric], metric: LeaderboardMetric,
                     name: (UUID) -> String) -> [LeaderboardEntry] {
        let source: Metric = switch metric {
        case .effort: .effortScore
        case .steps: .steps
        case .azm: .azm
        case .averageSleep, .longNights: .sleepMinutes
        }
        let byUser = Dictionary(grouping: rows.filter { $0.metric == source }, by: \.userID)
        let totals = byUser.map { user, rows -> (UUID, Double) in
            let values = rows.map(\.value)
            let total: Double = switch metric {
            case .averageSleep: values.reduce(0, +) / Double(values.count)
            case .longNights: Double(values.filter { $0 >= 420 }.count)
            default: values.reduce(0, +)
            }
            return (user, (total * 10).rounded() / 10)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : name($0.0) < name($1.0) }

        // Standard competition ranking: ties share a rank (1, 1, 3).
        var entries: [LeaderboardEntry] = []
        for (index, (user, total)) in totals.enumerated() {
            let rank = index > 0 && totals[index - 1].1 == total ? entries[index - 1].rank : index + 1
            entries.append(LeaderboardEntry(userID: user, displayName: name(user), avatarURL: nil, value: total, rank: rank))
        }
        return entries
    }
}

/// Invite codes: 8 characters without look-alikes, typed in any case with or without dashes.
nonisolated enum InviteCode {
    static let length = 8

    static func normalize(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isComplete(_ text: String) -> Bool {
        normalize(text).count == length
    }
}
