import Foundation
import Testing
@testable import App

struct ProfileDTOTests {
    @Test func decodesARowFromTheDatabase() throws {
        let json = """
        {"id": "10000000-0000-4000-8000-000000000001", "display_name": "Maya",
         "avatar_url": "https://example.supabase.co/storage/v1/object/public/avatars/a/b.jpg",
         "timezone": "America/New_York", "devices": ["apple_watch"]}
        """
        let profile = try JSONDecoder().decode(ProfileDTO.self, from: Data(json.utf8))
        #expect(profile.id == UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        #expect(profile.displayName == "Maya")
        #expect(profile.avatarURL?.lastPathComponent == "b.jpg")
        #expect(profile.timezone == "America/New_York")
        #expect(profile.devices == ["apple_watch"])
    }

    @Test func decodesAFreshProfileWithNoPhoto() throws {
        let json = """
        {"id": "10000000-0000-4000-8000-000000000001", "display_name": "",
         "avatar_url": null, "timezone": "UTC", "devices": []}
        """
        let profile = try JSONDecoder().decode(ProfileDTO.self, from: Data(json.utf8))
        #expect(profile.displayName.isEmpty)
        #expect(profile.avatarURL == nil)
    }

    @Test func columnsMatchCodingKeys() {
        let requested = Set(ProfileDTO.columns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let keys: [ProfileDTO.CodingKeys] = [.id, .displayName, .avatarURL, .timezone, .devices]
        #expect(requested == Set(keys.map(\.rawValue)))
    }

    @Test func updateSendsOnlyTheChangedColumns() throws {
        // The database only allows updating these columns; sending `id` would be refused.
        let update = ProfileUpdate(displayName: "Maya", timezone: "Europe/London")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any] ?? [:]
        #expect(Set(object.keys) == ["display_name", "timezone"])
        #expect(object["display_name"] as? String == "Maya")
    }

    @Test func updateEncodesThePhotoURLAsAString() throws {
        let url = try #require(URL(string: "https://example.supabase.co/storage/v1/object/public/avatars/a/b.jpg"))
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ProfileUpdate(avatarURL: url))) as? [String: Any]
        #expect(object?["avatar_url"] as? String == url.absoluteString)
    }
}
