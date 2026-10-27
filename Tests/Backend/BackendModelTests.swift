import Foundation
import Testing
@testable import App

/// The JSON the app sends and expects must match the database's column names.
struct BackendModelTests {
    let alice = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    let group = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000001")!

    func json(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        return try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] ?? [:]
    }

    func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    @Test func metricUploadUsesColumnNames() throws {
        let row = MetricRow(date: CivilDate(year: 2026, month: 10, day: 27), metric: .sleepMinutes, value: 412,
                            detail: ["deep": 70])
        let object = try json(MetricUpload(userID: alice, row: row))
        #expect(Set(object.keys) == ["user_id", "date", "metric", "value", "detail"])
        #expect(object["date"] as? String == "2026-10-27")
        #expect(object["metric"] as? String == "sleep_minutes")
        #expect((object["detail"] as? [String: Int])?["deep"] == 70)
    }

    @Test func profileUpdateSendsOnlyWhatChanged() throws {
        let object = try json(ProfileUpdate(displayName: "Maya"))
        #expect(Set(object.keys) == ["display_name"])
    }

    @Test func goalsUseTheirColumns() throws {
        let object = try json(GoalsRow(Goals(sleepMinutes: 480, steps: 10_000)))
        #expect(object["sleep_goal_minutes"] as? Int == 480)
        #expect(object["step_goal"] as? Int == 10_000)
    }

    @Test func sharingSendsHiddenDatesAsDates() throws {
        var setting = SharingSetting(userID: alice, groupID: group, category: .sleep, enabled: true)
        setting.hiddenDates = [CivilDate(year: 2026, month: 10, day: 26)]
        let object = try json(setting)
        #expect(object["hidden_dates"] as? [String] == ["2026-10-26"])
        #expect(object["category"] as? String == "sleep")
    }

    @Test func shareAllTurnsOnEveryCategory() {
        let settings = SharingSetting.shareAll(userID: alice, groupID: group)
        #expect(settings.map(\.category) == SharingCategory.allCases)
        #expect(settings.allSatisfy { $0.enabled })
    }

    @Test func newReactionLeavesTheAuthorToTheDatabase() throws {
        let object = try json(NewReaction(groupID: group, ownerID: alice, day: CivilDate(year: 2026, month: 10, day: 27),
                                          emoji: "👊"))
        #expect(Set(object.keys) == ["group_id", "owner_id", "day", "emoji"])
    }

    @Test func decodesAProfileWithoutAPhoto() throws {
        let profile = try decode(Profile.self, """
        {"id": "\(alice)", "display_name": "Alice", "avatar_url": "", "timezone": "UTC", "device_name": null}
        """)
        #expect(profile.displayName == "Alice")
        #expect(profile.avatarURL == nil)
    }

    @Test func decodesTheFeed() throws {
        let rows = try decode([FriendMetric].self, """
        [{"user_id": "\(alice)", "date": "2026-10-27", "metric": "sleep_minutes", "value": 412,
          "detail": {"deep": 70, "rem": 88.0}},
         {"user_id": "\(alice)", "date": "2026-10-27", "metric": "steps", "value": 8423.0, "detail": {}}]
        """)
        #expect(rows.count == 2)
        #expect(rows[0].detail["rem"] == 88)
        #expect(rows[1].value == 8423)
    }

    @Test func decodesALeaderboard() throws {
        let entries = try decode([LeaderboardEntry].self, """
        [{"user_id": "\(alice)", "display_name": "Alice", "avatar_url": null, "value": 61234.0, "rank": 1}]
        """)
        #expect(entries.first?.rank == 1)
        #expect(entries.first?.value == 61_234)
    }

    @Test func decodesAGroupAndItsPreview() throws {
        let info = try decode(GroupInfo.self, """
        {"id": "\(group)", "name": "Training Camp", "invite_code": "CAMP2345", "created_by": "\(alice)",
         "created_at": "2026-10-27T09:00:00.123456+00:00"}
        """)
        #expect(info.inviteCode == "CAMP2345")
        let preview = try decode(GroupPreview?.self, """
        {"name": "Training Camp", "members": [{"display_name": "Maya", "avatar_url": null}]}
        """)
        #expect(preview?.members.first?.displayName == "Maya")
        #expect(try decode(GroupPreview?.self, "null") == nil)
    }

    @Test func decodesAReaction() throws {
        let reaction = try decode(Reaction.self, """
        {"id": "\(UUID())", "group_id": "\(group)", "author_id": "\(alice)", "owner_id": "\(alice)",
         "day": "2026-10-27", "emoji": "🔥"}
        """)
        #expect(reaction.emoji == "🔥")
    }

    @Test(arguments: GroupChallengeKind.allCases)
    func everyGroupChallengeHasALeaderboard(kind: GroupChallengeKind) {
        #expect(LeaderboardMetric(kind).rawValue == kind.leaderboardMetric)
    }

    @Test func physiologyIsNeverRankable() {
        let names = Set(LeaderboardMetric.allCases.map(\.rawValue))
        #expect(names.isDisjoint(with: ["recovery", "recovery_score", "hrv", "hrv_ms", "resting_hr"]))
    }
}
