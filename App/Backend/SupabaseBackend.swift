import Foundation
import Supabase

/// The real backend: Supabase Auth (Google ID token), Postgres tables behind
/// row-level security, and a few RPCs. Every rule about who sees what lives in
/// the database (supabase/migrations), not here.
nonisolated struct SupabaseBackend: Backend {
    let client: SupabaseClient

    // MARK: Account

    func signIn(googleIDToken: String, accessToken: String?, rawNonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .google, idToken: googleIDToken, accessToken: accessToken, nonce: rawNonce))
        return session.user.id
    }

    func currentUserID() async -> UUID? {
        client.auth.currentUser?.id
    }

    func accountID() async -> String? {
        await currentUserID()?.uuidString.lowercased()
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        try await call { try await client.rpc("delete_my_account").execute() }
        await signOut()
    }

    // MARK: Profile and goals

    func myProfile() async throws -> Profile {
        let id = try await userID()
        return try await call {
            try await client.from("profiles").select().eq("id", value: id).single().execute().value
        }
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        let id = try await userID()
        try await call {
            try await client.from("profiles").update(update, returning: .minimal).eq("id", value: id).execute()
        }
    }

    func myGoals() async throws -> Goals {
        let id = try await userID()
        let row: GoalsRow = try await call {
            try await client.from("profile_private").select("sleep_goal_minutes, step_goal")
                .eq("user_id", value: id).single().execute().value
        }
        return row.goals
    }

    func updateGoals(_ goals: Goals) async throws {
        let id = try await userID()
        try await call {
            try await client.from("profile_private").update(GoalsRow(goals), returning: .minimal)
                .eq("user_id", value: id).execute()
        }
    }

    // MARK: Groups

    func myGroups() async throws -> [GroupInfo] {
        // Row-level security returns only groups you belong to.
        try await call {
            try await client.from("groups").select("id, name, invite_code, created_by")
                .order("created_at").execute().value
        }
    }

    func members(of groupID: UUID) async throws -> [Member] {
        let memberships: [MembershipRow] = try await call {
            try await client.from("group_members").select("user_id, role").eq("group_id", value: groupID)
                .order("joined_at").execute().value
        }
        guard !memberships.isEmpty else { return [] }
        let profiles: [Profile] = try await call {
            try await client.from("profiles").select("id, display_name, avatar_url, timezone, device_name")
                .in("id", values: memberships.map(\.userID)).execute().value
        }
        let byID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return memberships.compactMap { membership in
            byID[membership.userID].map { Member(profile: $0, isOwner: membership.role == "owner") }
        }
    }

    func createGroup(named name: String) async throws -> GroupInfo {
        try await call { try await client.rpc("create_group", params: ["group_name": name]).execute().value }
    }

    func joinGroup(code: String) async throws -> GroupInfo {
        try await call { try await client.rpc("join_group", params: ["code": code]).execute().value }
    }

    func previewGroup(code: String) async throws -> GroupPreview? {
        try await call { try await client.rpc("preview_group", params: ["code": code]).execute().value }
    }

    func leaveGroup(_ groupID: UUID) async throws {
        let id = try await userID()
        try await call {
            try await client.from("group_members").delete(returning: .minimal)
                .eq("group_id", value: groupID).eq("user_id", value: id).execute()
        }
    }

    // MARK: Sharing

    func sharing(in groupID: UUID) async throws -> [SharingSetting] {
        try await call {
            try await client.from("sharing_settings").select("user_id, group_id, category, enabled, hidden_dates")
                .eq("group_id", value: groupID).execute().value
        }
    }

    func saveSharing(_ settings: [SharingSetting]) async throws {
        guard !settings.isEmpty else { return }
        try await call {
            try await client.from("sharing_settings")
                .upsert(settings, onConflict: "user_id,group_id,category", returning: .minimal).execute()
        }
    }

    // MARK: Friends' numbers

    func upsertMetrics(_ rows: [MetricRow]) async throws {
        let id = try await userID()
        try await call {
            try await client.from("daily_metrics")
                .upsert(rows.map { MetricUpload(userID: id, row: $0) }, onConflict: "user_id,date,metric",
                        returning: .minimal)
                .execute()
        }
    }

    func feed(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [FriendMetric] {
        try await call {
            try await client.rpc("group_feed", params: [
                "p_group_id": groupID.uuidString, "from_date": start.description, "to_date": end.description,
            ]).execute().value
        }
    }

    func leaderboard(groupID: UUID, weekStart: CivilDate, metric: LeaderboardMetric) async throws -> [LeaderboardEntry] {
        try await call {
            try await client.rpc("weekly_leaderboard", params: [
                "p_group_id": groupID.uuidString, "week_start": weekStart.description, "metric": metric.rawValue,
            ]).execute().value
        }
    }

    // MARK: Reactions

    func reactions(groupID: UUID, from start: CivilDate, through end: CivilDate) async throws -> [Reaction] {
        try await call {
            try await client.from("reactions").select("id, group_id, author_id, owner_id, day, emoji")
                .eq("group_id", value: groupID)
                .gte("day", value: start.description).lte("day", value: end.description)
                .order("created_at").execute().value
        }
    }

    func addReaction(groupID: UUID, ownerID: UUID, day: CivilDate, emoji: String) async throws -> Reaction {
        try await call {
            try await client.from("reactions")
                .insert(NewReaction(groupID: groupID, ownerID: ownerID, day: day, emoji: emoji), returning: .representation)
                .select("id, group_id, author_id, owner_id, day, emoji").single().execute().value
        }
    }

    func removeReaction(id: UUID) async throws {
        try await call { try await client.from("reactions").delete(returning: .minimal).eq("id", value: id).execute() }
    }

    // MARK: Helpers

    private func userID() async throws -> UUID {
        guard let id = await currentUserID() else { throw BackendError.notSignedIn }
        return id
    }

    /// Runs a request and turns database errors into `BackendError`.
    @discardableResult
    private func call<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch let error as PostgrestError {
            throw Self.backendError(code: error.code, message: error.message)
        }
    }

    static func backendError(code: String?, message: String) -> BackendError {
        switch code {
        case "P0002": .unknownInviteCode
        case "42501": .notSignedIn
        default: .server(message)
        }
    }
}
