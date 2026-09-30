import Foundation

/// A row of `public.profiles`: what group-mates may see about a person.
nonisolated struct ProfileDTO: Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var avatarURL: URL?
    var timezone: String
    var devices: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case timezone
        case devices
    }

    /// The columns to request, matching CodingKeys.
    static let columns = "id, display_name, avatar_url, timezone, devices"
}

/// The profile columns the app may change. The database only grants UPDATE on
/// these columns, so the payload must never include `id`. A nil value is left
/// out of the JSON and leaves that column unchanged.
nonisolated struct ProfileUpdate: Encodable, Equatable, Sendable {
    var displayName: String?
    var avatarURL: URL?
    var timezone: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case timezone
    }
}
