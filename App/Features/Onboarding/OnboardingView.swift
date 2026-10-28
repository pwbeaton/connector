import AuthenticationServices
import SwiftUI

/// Hosts the onboarding steps with a slim progress bar on top.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .welcome {
                ProgressBar(fraction: Double(model.stepNumber) / Double(OnboardingModel.Step.allCases.count - 1),
                            height: 4)
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
            }
            Group {
                switch model.step {
                case .welcome: WelcomeView(model: model)
                case .device: DeviceCheckView(model: model)
                case .goals: GoalsView(model: model)
                case .group: GroupStepView(model: model)
                case .sharing: SharingStepView(model: model)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
        }
        .animation(.snappy, value: model.step)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// The layout every step shares: title, text, content, and buttons at the bottom.
struct OnboardingPage<Content: View, Buttons: View>: View {
    let title: String
    let message: String
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title).font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message).font(.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                }
                .padding(Theme.screenPadding)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) { buttons }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    let model: OnboardingModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            HeroRings()
                .frame(height: 220)
            VStack(spacing: 12) {
                Text("Train together.\nRecover smarter.")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Daily Recovery, Sleep, and Effort scores from your Fitbit Air, plus streaks, challenges, and leaderboards with friends.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 28)
            Spacer(minLength: 24)
            VStack(spacing: 14) {
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.recoveryRest).multilineTextAlignment(.center)
                }
                Button {
                    Task { await model.continueWithGoogle(authenticate: authenticate) }
                } label: {
                    HStack(spacing: 10) {
                        if model.isBusy { ProgressView().tint(.white) } else { Image(systemName: "g.circle.fill") }
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.isBusy)
                Label("Your raw health data stays on this iPhone. Friends see only the daily scores you choose to share.",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 12)
        }
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        do {
            return try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: callbackScheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw GoogleAuthError.cancelled
        }
    }
}

/// Three nested score rings, the app's signature image.
struct HeroRings: View {
    var body: some View {
        ZStack {
            ring(0.78, Theme.recoveryGo, size: 210)
            ring(0.84, Theme.sleep, size: 160)
            ring(0.62, Theme.effort, size: 110)
        }
        .accessibilityHidden(true)
    }

    private func ring(_ fraction: Double, _ color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 16)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 10)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Device check

struct DeviceCheckView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage(title: "Your tracker",
                       message: "We're reading your Fitbit Air's history from Google Health so your scores, trends, and tier work from day one.") {
            VStack(spacing: 12) {
                checkRow(done: model.deviceChecked, title: deviceTitle, detail: deviceDetail)
                checkRow(done: model.historyLoaded, title: "90 days of history",
                         detail: model.historyLoaded ? "Scores computed" : "Downloading and scoring…")
            }
        } buttons: {
            Button("Continue") { model.step = .goals }
                .buttonStyle(.primary)
                .disabled(!model.historyLoaded)
        }
        .task { if !model.historyLoaded { await model.checkDevice() } }
    }

    private var deviceTitle: String {
        guard model.deviceChecked else { return "Looking for your tracker…" }
        return model.device.map { "\($0.name) found" } ?? "No tracker found yet"
    }

    private var deviceDetail: String {
        guard let device = model.device else {
            if model.accountNotLinked { return GoogleHealthError.accountNotLinkedMessage }
            return model.deviceChecked ? "Pair your Fitbit Air in the Google Health app. You can continue anyway." : " "
        }
        var parts: [String] = []
        if let lastSync = device.lastSync { parts.append("synced \(Format.ago(lastSync))") }
        if let battery = device.batteryPercent { parts.append("battery \(battery)%") }
        return parts.joined(separator: " · ")
    }

    private func checkRow(done: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.recoveryGo)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Goals

struct GoalsView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(title: "Your goals",
                       message: "These drive your streaks and Sleep score. The defaults suit most people; change them any time.") {
            VStack(spacing: 12) {
                goalCard(title: "Sleep", value: Format.duration(minutes: model.sleepGoalMinutes), color: Theme.sleep,
                         symbol: "moon.fill") {
                    Stepper("Sleep goal", value: $model.sleepGoalMinutes, in: 300...600, step: 15).labelsHidden()
                }
                goalCard(title: "Steps", value: Format.count(model.stepGoal), color: Theme.effort,
                         symbol: "figure.walk") {
                    Stepper("Step goal", value: $model.stepGoal, in: 2_000...30_000, step: 500).labelsHidden()
                }
            }
        } buttons: {
            Button("Continue") { Task { await model.saveGoals() } }
                .buttonStyle(.primary)
                .disabled(model.isBusy)
        }
    }

    private func goalCard<Control: View>(title: String, value: String, color: Color, symbol: String,
                                         @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Image(systemName: symbol).font(.title2).foregroundStyle(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).sectionLabel()
                Text(value).font(.scoreNumber(28)).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            control()
        }
        .card()
    }
}

// MARK: - Group

struct GroupStepView: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focusedField: Field?

    enum Field { case code, name }

    var body: some View {
        OnboardingPage(title: "Your crew",
                       message: "Join a friend's group with their invite code, or start one and invite them.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Join with a code").sectionLabel()
                VStack(alignment: .leading, spacing: 12) {
                    TextField("CAMP2345", text: $model.inviteCode)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .code)
                        .onChange(of: model.inviteCode) { Task { await model.lookUpInviteCode() } }
                    if let preview = model.preview {
                        HStack(spacing: -8) {
                            ForEach(Array(preview.members.prefix(5).enumerated()), id: \.offset) { _, person in
                                AvatarView(name: person.displayName, url: person.avatarURL.flatMap(URL.init(string:)), size: 32)
                                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                            }
                            Text("\(preview.name) · \(preview.members.count) members")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.leading, 16)
                        }
                    }
                    Button("Join group") { Task { await model.joinGroup() } }
                        .buttonStyle(.primary)
                        .disabled(!InviteCode.isComplete(model.inviteCode) || model.isBusy)
                }
                .card()

                Text("Or start a group").sectionLabel().padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Group name, e.g. Morning Crew", text: $model.newGroupName)
                        .font(.title3)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                    Button("Create group") { Task { await model.createGroup() } }
                        .buttonStyle(.secondary)
                        .disabled(model.newGroupName.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                }
                .card()

                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.recoveryRest)
                }
            }
        } buttons: {
            Button("Skip for now") { model.skipGroup() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
        }
    }
}

// MARK: - Sharing

struct SharingStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(title: model.createdGroup ? "Group created" : "You're in",
                       message: "Choose what \(model.group?.name ?? "your group") can see. Your raw data never leaves this iPhone, and you can hide any day later.") {
            VStack(spacing: 12) {
                if model.createdGroup, let group = model.group {
                    InviteCard(group: group)
                }
                VStack(spacing: 0) {
                    ForEach(SharingCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { model.sharing.contains(category) },
                            set: { isOn in
                                if isOn { model.sharing.insert(category) } else { model.sharing.remove(category) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title).font(.headline).foregroundStyle(Theme.textPrimary)
                                Text(category.detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 10)
                        if category != SharingCategory.allCases.last { Divider() }
                    }
                }
                .card()
                Text("Leaderboards only rank Effort, steps, and sleep. Recovery, HRV, and resting heart rate are never ranked.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } buttons: {
            Button("Start training") { Task { await model.finish() } }
                .buttonStyle(.primary)
                .disabled(model.isBusy)
        }
    }
}

/// The invite code with a share button.
struct InviteCard: View {
    let group: GroupInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invite code").sectionLabel()
            Text(group.inviteCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            ShareLink(item: InviteText.message(for: group)) {
                Label("Invite friends", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)
        }
        .card()
    }
}
