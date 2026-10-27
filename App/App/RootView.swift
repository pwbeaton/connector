import SwiftUI

/// Decides which screen the app shows.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.mode {
            case .demo, .live:
                FoundationPreviewView()
            case .setupNeeded(let reason):
                SetupNeededView(reason: reason) { model.enterDemo() }
            }
        }
        .tint(Theme.effort)
    }
}

/// Temporary first screen while the real tabs are built (milestone M0).
private struct FoundationPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Today").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    scoreTile("Recovery", value: 78, color: Theme.recoveryGo)
                    scoreTile("Sleep", value: 84, color: Theme.sleep)
                    scoreTile("Effort", value: 41, color: Theme.effort)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
    }

    private func scoreTile(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionLabel()
            Text("\(value)").font(.scoreNumber(40)).foregroundStyle(color)
        }
        .card()
    }
}

/// Shown when the build is missing Supabase or Google settings.
struct SetupNeededView: View {
    let reason: AppConfig.LoadError
    let onExploreDemo: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(Theme.effort)
                .accessibilityHidden(true)
            Text("Setup needed").font(.title.bold()).foregroundStyle(Theme.textPrimary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Explore with sample data", action: onExploreDemo)
                .buttonStyle(.primary)
        }
        .padding(Theme.screenPadding)
        .background(Theme.background)
    }

    private var message: String {
        switch reason {
        case .missingSecrets, .invalidURL:
            "Add your Supabase URL and anon key to Config/Secrets.xcconfig (see docs/DEVICE-SETUP.md), then build again."
        case .missingGoogleClient:
            "Add your Google iOS client ID to Config/Identity.xcconfig (see docs/SETUP-GOOGLE.md), then build again."
        }
    }
}
