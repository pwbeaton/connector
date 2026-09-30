import PhotosUI
import SwiftUI

/// Name and photo: how friends will see you. The time zone is detected, not asked.
struct ProfileSetupView: View {
    @State private var model: ProfileSetupModel
    private let onSaved: (ProfileDTO) -> Void

    init(profile: ProfileDTO, givenNameFromApple: String?, profiles: ProfileRepository,
         onSaved: @escaping (ProfileDTO) -> Void) {
        _model = State(initialValue: ProfileSetupModel(
            profile: profile, givenNameFromApple: givenNameFromApple, profiles: profiles))
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Your profile")
                        .font(.largeTitle.bold())
                    Text("This is how friends will see you in your groups.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                PhotosPicker(selection: $model.photoItem, matching: .images) {
                    AvatarView(name: model.displayName, url: model.existingAvatarURL,
                               localImage: model.pickedImage, size: 112)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 34))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                                .background(Circle().fill(.background))
                        }
                }
                .accessibilityLabel("Choose a profile photo")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("First name", text: $model.displayName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .font(.title3)
                        .padding()
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    if let hint = model.nameHint {
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Text(model.timeZoneName)
                } label: {
                    Label("Time zone", systemImage: "globe")
                }
                .accessibilityHint("Detected automatically")

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Theme.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    if let saved = await model.save() { onSaved(saved) }
                }
            } label: {
                if model.isSaving { ProgressView().tint(.white) } else { Text("Continue") }
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .task(id: model.photoItem) {
            await model.loadPickedPhoto()
        }
    }
}
