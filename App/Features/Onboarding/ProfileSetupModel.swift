import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Drives the profile screen: name, photo, and the automatically detected time zone.
@Observable
final class ProfileSetupModel {
    var displayName: String
    var photoItem: PhotosPickerItem?
    private(set) var pickedImage: UIImage?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    let existingAvatarURL: URL?
    /// Detected, not asked: the identifier (e.g. "America/New_York") is saved,
    /// and a friendly name is shown.
    let timeZone = TimeZone.current

    private let userID: UUID
    private let profiles: ProfileRepository
    private var pickedJPEG: Data?

    init(profile: ProfileDTO, givenNameFromApple: String?, profiles: ProfileRepository) {
        userID = profile.id
        self.profiles = profiles
        existingAvatarURL = profile.avatarURL
        // Prefill: the saved name, else the first name Apple shared at sign-in.
        displayName = profile.displayName.isEmpty ? (givenNameFromApple ?? "") : profile.displayName
    }

    var timeZoneName: String {
        timeZone.localizedName(for: .generic, locale: .current) ?? timeZone.identifier
    }

    var canSave: Bool {
        DisplayName.clean(displayName) != nil && !isSaving
    }

    var nameHint: String? {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).count > DisplayName.maxLength
            ? "Keep it to \(DisplayName.maxLength) characters or fewer."
            : nil
    }

    /// Loads the photo chosen in the picker and prepares a small JPEG.
    func loadPickedPhoto() async {
        guard let photoItem else { return }
        errorMessage = nil
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = AvatarImage.jpegData(from: image)
            else {
                errorMessage = "That photo couldn't be used. Try another one."
                return
            }
            pickedJPEG = jpeg
            pickedImage = UIImage(data: jpeg)
        } catch {
            errorMessage = "That photo couldn't be loaded. Try another one."
        }
    }

    /// Uploads the photo (if a new one was picked) and saves the profile.
    /// Returns the saved profile, or nil if saving failed.
    func save() async -> ProfileDTO? {
        guard let name = DisplayName.clean(displayName) else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var avatarURL: URL?
            if let pickedJPEG {
                avatarURL = try await profiles.uploadAvatar(userID: userID, jpegData: pickedJPEG)
            }
            return try await profiles.updateProfile(
                userID: userID,
                ProfileUpdate(displayName: name, avatarURL: avatarURL, timezone: timeZone.identifier)
            )
        } catch {
            errorMessage = "We couldn't save your profile. Check your connection and try again."
            return nil
        }
    }
}
