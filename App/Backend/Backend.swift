import Foundation

// The app's view of the server: accounts, profiles, groups, sharing, friends'
// numbers, leaderboards, and reactions. SupabaseBackend talks to Supabase;
// DemoBackend serves sample friends; tests use fakes.

nonisolated protocol Backend: MetricUploading {
    // Account
    /// Signs in with the Google ID token from "Continue with Google". The raw nonce
    /// lets Supabase check the token was issued for this sign-in.
    func signIn(googleIDToken: String, accessToken: String?, rawNonce: String) async throws -> UUID
    func currentUserID() async -> UUID?
    func signOut() async
    /// Deletes the account and everything in it.
    func deleteAccount() async throws

    // Profile and goals
    func myProfile() async throws -> Profile
    func updateProfile(_ update: ProfileUpdate) async throws
    func myGoals() async throws -> Goals
    func updateGoals(_ goals: Goals) async throws

    // Groups
    func myGroups() async throws -> [GroupInfo]
    func members(of groupID: UUID) async throws -> [Member]
    func createGroup(named name: String) async throws -> GroupInfo
    /// Throws `BackendError.unknownInviteCode` when no group has the code.
    func joinGroup(code: String) async throws -> GroupInfo
    /// The group's name and members, for the Join screen. Nil for an unknown code.
    func previewGroup(code: String) async throws -> GroupPreview?
    func leaveGroup(_ groupID: UUID) async throws

    // Sharing (yours only)
    func sharing(in groupID: UUID) async throws -> [SharingSetting]
    func saveSharing(_ settings: [SharingSetting]) async throws

    // Friends' numbers
    /// Daily summaries group-mates share with this group (yours included).
    func feed(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [FriendMetric]
    func leaderboard(groupID: UUID, weekStart: CivilDate, metric: LeaderboardMetric) async throws -> [LeaderboardEntry]

    // Reactions
    func reactions(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [Reaction]
    func addReaction(groupID: UUID, ownerID: UUID, day: CivilDate, emoji: String) async throws -> Reaction
    func removeReaction(id: UUID) async throws
}

nonisolated enum BackendError: Error, Equatable {
    case notSignedIn
    case unknownInviteCode
    case server(String)
}

// MARK: - Models (column names match supabase/migrations)

nonisolated struct Profile: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var displayName: String
    var avatarURLString: String?
    var timezone: String
    var deviceName: String?

    var avatarURL: URL? { avatarURLString.flatMap { $0.isEmpty ? nil : URL(string: $0) } }

    enum CodingKeys: String, CodingKey {
        case id, timezone
        case displayName = "display_name"
        case avatarURLString = "avatar_url"
        case deviceName = "device_name"
    }
}

/// Profile fields to change; nil fields are left alone (they aren't sent).
nonisolated struct ProfileUpdate: Encodable, Equatable, Sendable {
    var displayName: String?
    var timezone: String?
    var deviceName: String?

    enum CodingKeys: String, CodingKey {
        case timezone
        case displayName = "display_name"
        case deviceName = "device_name"
    }
}

/// The row in profile_private (goals). Only you can read it.
nonisolated struct GoalsRow: Codable, Equatable, Sendable {
    var sleepGoalMinutes: Int
    var stepGoal: Int

    init(_ goals: Goals) {
        sleepGoalMinutes = goals.sleepMinutes
        stepGoal = goals.steps
    }

    var goals: Goals { Goals(sleepMinutes: sleepGoalMinutes, steps: stepGoal) }

    enum CodingKeys: String, CodingKey {
        case sleepGoalMinutes = "sleep_goal_minutes"
        case stepGoal = "step_goal"
    }
}

nonisolated struct GroupInfo: Codable, Equatable, Sendable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var inviteCode: String
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case createdBy = "created_by"
    }
}

nonisolated struct Member: Equatable, Sendable, Identifiable {
    var profile: Profile
    var isOwner: Bool
    var id: UUID { profile.id }
}

/// A row of group_members.
nonisolated struct MembershipRow: Codable, Equatable, Sendable {
    var userID: UUID
    var role: String

    enum CodingKeys: String, CodingKey {
        case role
        case userID = "user_id"
    }
}

nonisolated struct GroupPreview: Codable, Equatable, Sendable {
    nonisolated struct Person: Codable, Equatable, Sendable {
        var displayName: String
        var avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    var name: String
    var members: [Person]
}

nonisolated struct SharingSetting: Codable, Equatable, Sendable {
    var userID: UUID
    var groupID: UUID
    var category: SharingCategory
    var enabled: Bool
    /// Days this category is hidden from the group.
    var hiddenDates: [CivilDate] = []

    enum CodingKeys: String, CodingKey {
        case category, enabled
        case userID = "user_id"
        case groupID = "group_id"
        case hiddenDates = "hidden_dates"
    }

    /// Everything on: the default when joining or creating a group (one tap to continue).
    static func shareAll(userID: UUID, groupID: UUID) -> [SharingSetting] {
        SharingCategory.allCases.map { SharingSetting(userID: userID, groupID: groupID, category: $0, enabled: true) }
    }
}

/// One daily summary a group-mate shares (from the group_feed RPC).
nonisolated struct FriendMetric: Codable, Equatable, Sendable {
    var userID: UUID
    var date: CivilDate
    var metric: Metric
    var value: Double
    var detail: [String: Double]

    enum CodingKeys: String, CodingKey {
        case date, metric, value, detail
        case userID = "user_id"
    }
}

/// Upload payload for daily_metrics.
nonisolated struct MetricUpload: Encodable, Sendable {
    var userID: UUID
    var row: MetricRow

    enum CodingKeys: String, CodingKey {
        case date, metric, value, detail
        case userID = "user_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(row.date, forKey: .date)
        try container.encode(row.metric, forKey: .metric)
        try container.encode(row.value, forKey: .value)
        try container.encode(row.detail, forKey: .detail)
    }
}

/// What can be ranked. Recovery, HRV, and resting HR never are.
nonisolated enum LeaderboardMetric: String, Codable, Sendable, CaseIterable, Identifiable {
    case effort, steps, azm
    case averageSleep = "avg_sleep"
    case longNights = "long_nights"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .effort: "Effort"
        case .steps: "Steps"
        case .azm: "Zone minutes"
        case .averageSleep: "Avg sleep"
        case .longNights: "7h+ nights"
        }
    }

    init(_ challenge: GroupChallengeKind) {
        self = LeaderboardMetric(rawValue: challenge.leaderboardMetric) ?? .steps
    }
}

nonisolated struct LeaderboardEntry: Codable, Equatable, Sendable, Identifiable {
    var userID: UUID
    var displayName: String
    var avatarURL: String?
    var value: Double
    var rank: Int

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case value, rank
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

nonisolated struct Reaction: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var groupID: UUID
    var authorID: UUID
    var ownerID: UUID
    var day: CivilDate
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case id, day, emoji
        case groupID = "group_id"
        case authorID = "author_id"
        case ownerID = "owner_id"
    }

    /// The reactions offered on a day card.
    static let choices = ["👊", "🔥", "💪", "😴", "👏"]
}

/// Insert payload for reactions (author_id is filled in by the database).
nonisolated struct NewReaction: Encodable, Sendable {
    var groupID: UUID
    var ownerID: UUID
    var day: CivilDate
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case day, emoji
        case groupID = "group_id"
        case ownerID = "owner_id"
    }
}
