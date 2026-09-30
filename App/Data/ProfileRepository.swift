import Foundation
import Supabase

/// Reading and saving the signed-in user's profile and photo.
final class ProfileRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadProfile(userID: UUID) async throws -> ProfileDTO {
        try await client.from("profiles")
            .select(ProfileDTO.columns)
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    /// Saves the changed columns and returns the updated profile.
    func updateProfile(userID: UUID, _ update: ProfileUpdate) async throws -> ProfileDTO {
        try await client.from("profiles")
            .update(update)
            .eq("id", value: userID)
            .select(ProfileDTO.columns)
            .single()
            .execute()
            .value
    }

    /// Uploads a JPEG to the public `avatars` bucket and returns its URL.
    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> URL {
        let path = AvatarPath.make(userID: userID)
        let bucket = client.storage.from("avatars")
        try await bucket.upload(
            path,
            data: jpegData,
            // Each upload has a new random name, so it can be cached for a year.
            options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg")
        )
        return try bucket.getPublicURL(path: path)
    }
}

/// Where a user's photo is stored: `<user id>/<random id>.jpg`.
nonisolated enum AvatarPath {
    static func make(userID: UUID, fileID: UUID = UUID()) -> String {
        // Storage policies compare the folder with auth.uid()::text, which
        // Postgres writes in lowercase; Swift's uuidString is uppercase.
        "\(userID.uuidString.lowercased())/\(fileID.uuidString.lowercased()).jpg"
    }
}
