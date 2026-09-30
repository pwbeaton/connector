import AuthenticationServices
import SwiftUI

/// The first screen: what the app is, and one button.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.colorScheme) private var colorScheme

    init(auth: AuthRepository) {
        _model = State(initialValue: SignInModel(auth: auth))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(Bundle.main.displayName)
                    .font(.largeTitle.bold())
                Text("Share sleep, recovery, and workouts with your friends, whatever tracker they wear.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.continue) { request in
                model.prepare(request)
            } onCompletion: { result in
                model.handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .disabled(model.isSigningIn)
            .overlay {
                if model.isSigningIn { ProgressView() }
            }
        }
        .padding(24)
    }
}

extension Bundle {
    /// The name shown under the app icon (CFBundleDisplayName).
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }
}
