import SwiftUI

/// Your tier, badges, goals, sharing, tracker, and account.
struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var draftGoals: Goals?
    @State private var confirmingDelete = false
    @State private var confirmingLeave = false

    private var health: HealthModel { session.health }
    private var team: TeamModel { session.team }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                TierCard(tier: health.snapshot.tier)
                BadgesSection(earned: health.snapshot.badges)
                goalsSection
                sharingSection
                trackerSection
                accountSection
                Text("Scores are estimates to guide training, not medical advice.\nVersion \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.screenPadding)
        }
        .defaultScrollAnchor(session.options.startsAtBottom ? .bottom : .top)
        .background(Theme.background.ignoresSafeArea())
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { try? await session.deleteAccount() } }
        } message: {
            Text("This deletes your profile, groups you own alone, and every number you've shared. Data on this iPhone is erased too.")
        }
        .confirmationDialog("Leave \(team.selectedGroup?.name ?? "this group")?", isPresented: $confirmingLeave,
                            titleVisibility: .visible) {
            Button("Leave group", role: .destructive) {
                if let group = team.selectedGroup { Task { await team.leave(group, today: health.today) } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(name: session.profile?.displayName ?? "You", url: session.profile?.avatarURL, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.profile?.displayName ?? "You").font(.title.bold()).foregroundStyle(Theme.textPrimary)
                Label(health.snapshot.tier.tier.title, systemImage: "shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(health.snapshot.tier.tier.color)
            }
            Spacer()
        }
    }

    // MARK: Goals

    private var goalsSection: some View {
        let goals = draftGoals ?? health.goals
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Goals")
            VStack(spacing: 12) {
                Stepper(value: Binding(get: { goals.sleepMinutes }, set: { draftGoals = Goals(sleepMinutes: $0, steps: goals.steps) }),
                        in: 300...600, step: 15) {
                    settingLabel("Sleep", value: Format.duration(minutes: goals.sleepMinutes), symbol: "moon.fill", color: Theme.sleep)
                }
                Divider()
                Stepper(value: Binding(get: { goals.steps }, set: { draftGoals = Goals(sleepMinutes: goals.sleepMinutes, steps: $0) }),
                        in: 2_000...30_000, step: 500) {
                    settingLabel("Steps", value: Format.count(goals.steps), symbol: "figure.walk", color: Theme.effort)
                }
                if let draftGoals, draftGoals != health.goals {
                    Button("Save goals") {
                        Task {
                            await health.updateGoals(draftGoals)
                            self.draftGoals = nil
                        }
                    }
                    .buttonStyle(.primary)
                }
            }
            .card()
        }
    }

    // MARK: Sharing

    @ViewBuilder private var sharingSection: some View {
        if let group = team.selectedGroup {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Sharing", trailing: group.name)
                VStack(spacing: 12) {
                    ForEach(SharingCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { team.isSharing(category) },
                                             set: { on in Task { await team.setSharing(category, enabled: on, today: health.today) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text(category.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Divider()
                    }
                    Toggle(isOn: Binding(get: { hidesToday }, set: { hide in Task { await setHideToday(hide) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide today").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("Keep today's numbers from \(group.name). Streaks and scores still count.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Invite code").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(group.inviteCode).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                    }
                    Button("Leave group", role: .destructive) { confirmingLeave = true }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .card()
            }
        }
    }

    private var hidesToday: Bool {
        SharingCategory.allCases.allSatisfy { team.isHidden($0, on: health.today) }
    }

    private func setHideToday(_ hide: Bool) async {
        for category in SharingCategory.allCases {
            await team.setHidden(category, on: health.today, hidden: hide, today: health.today)
        }
    }

    // MARK: Tracker

    private var trackerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Tracker")
            VStack(alignment: .leading, spacing: 12) {
                settingLabel(health.device?.name ?? "Fitbit Air",
                             value: health.device?.lastSync.map { "synced \(Format.ago($0))" } ?? "not found",
                             symbol: "applewatch.side.right", color: Theme.effort)
                if let battery = health.device?.batteryPercent {
                    settingLabel("Battery", value: "\(battery)%", symbol: "battery.75percent", color: Theme.recoveryGo)
                }
                if let lastSync = health.state.lastSyncAt {
                    settingLabel("Last app sync", value: Format.ago(lastSync), symbol: "arrow.triangle.2.circlepath",
                                 color: Theme.textSecondary)
                }
                if !session.isDemo {
                    Button("Reconnect Fitbit") {
                        Task {
                            await session.reconnectGoogle { url, scheme in
                                try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: scheme)
                            }
                        }
                    }
                    .buttonStyle(.secondary)
                }
            }
            .card()
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Account")
            VStack(spacing: 0) {
                Button("Sign out") { Task { await session.signOut() } }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Divider()
                Button("Delete account", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .card()
        }
    }

    private func settingLabel(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}

// MARK: - Tier

struct TierCard: View {
    let tier: TierState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training tier").sectionLabel()
                Spacer()
                Text("\(tier.consistency)% consistency").font(.caption).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 14) {
                Image(systemName: tier.tier == .elite ? "crown.fill" : "shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(tier.tier.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.tier.title).font(.title.bold()).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let next = tier.tier.next {
                ProgressBar(fraction: Double(tier.consistency) / Double(max(1, next.minimumConsistency)), color: next.color)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if tier.isCalibrating { return "Calibrating: your tier settles after 7 days of data." }
        guard let next = tier.tier.next, let points = tier.pointsToNextTier else {
            return "The top tier. Hit your goals to stay here."
        }
        return "\(points) points to \(next.title). Share of sleep, step, and Effort goals hit over 28 days."
    }
}

// MARK: - Badges

struct BadgesSection: View {
    let earned: [EarnedBadge]
    @State private var selected: BadgeDefinition?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        let earnedDates = Dictionary(earned.map { ($0.id, $0.earnedOn) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Badges", trailing: "\(earnedDates.count) of \(Badges.all.count)")
            VStack(alignment: .leading, spacing: 14) {
                Text("Badges mark milestones in sleep, activity, recovery, and consistency. Gold ones are earned; tap any badge to see what it takes.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Badges.all) { badge in
                        let isEarned = earnedDates[badge.id] != nil
                        Button { selected = badge } label: {
                            VStack(spacing: 6) {
                                BadgeIcon(badge: badge, isEarned: isEarned, size: 52)
                                Text(badge.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(isEarned ? Theme.textPrimary : Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                Text(badge.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(badge.title), \(isEarned ? "earned" : "locked"): \(badge.detail)")
                        .accessibilityHint("Shows what this badge means")
                    }
                }
            }
            .card()
        }
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge, earnedOn: earnedDates[badge.id])
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }
}

struct BadgeIcon: View {
    let badge: BadgeDefinition
    let isEarned: Bool
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: badge.symbol)
            .font(.system(size: size * 0.42))
            .foregroundStyle(isEarned ? Theme.gold : Theme.textSecondary.opacity(0.4))
            .frame(width: size, height: size)
            .background(isEarned ? Theme.gold.opacity(0.14) : Theme.surfaceRaised, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if !isEarned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.18, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(size * 0.08)
                        .background(Theme.surface, in: Circle())
                }
            }
    }
}

/// What a badge means, how to earn it, and when you did.
struct BadgeDetailSheet: View {
    let badge: BadgeDefinition
    let earnedOn: CivilDate?

    var body: some View {
        VStack(spacing: 16) {
            BadgeIcon(badge: badge, isEarned: earnedOn != nil, size: 88)
                .padding(.top, 28)
            VStack(spacing: 6) {
                Text(badge.title).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                Label(earnedOn.map { "Earned \($0.noon.formatted(.dateTime.month(.wide).day().year()))" } ?? "Not earned yet",
                      systemImage: earnedOn == nil ? "lock.fill" : "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(earnedOn == nil ? Theme.textSecondary : Theme.gold)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to earn it").sectionLabel()
                    Text(badge.detail + ".").font(.body).foregroundStyle(Theme.textPrimary)
                }
                if !badge.why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters").sectionLabel()
                        Text(badge.why).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenPadding)
    }
}
