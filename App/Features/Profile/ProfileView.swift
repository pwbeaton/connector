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
        PlutoScreen(title: session.profile?.displayName ?? "You", subtitle: "\(health.snapshot.tier.tier.title) tier",
                    startsAtBottom: session.options.startsAtBottom) {
            header
            TierCard(tier: health.snapshot.tier).padding(.top, 8)
            BadgesSection(earned: health.snapshot.badges)
            goalsSection
            sharingSection
            trackerSection
            accountSection
            Text("Pluto · Version \(appVersion)\nScores are estimates to guide training, not medical advice.")
                .font(.archivo(12))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
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
        HStack(spacing: 16) {
            Group {
                if let url = session.profile?.avatarURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { avatarInitial }
                    }
                } else {
                    avatarInitial
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(session.profile?.displayName ?? "You").screenTitle(36).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    TierHexagon(tier: health.snapshot.tier.tier, size: 16, showsChevrons: false)
                    Text("\(health.snapshot.tier.tier.title) tier").font(.archivo(14, .semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var avatarInitial: some View {
        Theme.teal.overlay {
            Text(String(Initials.from(session.profile?.displayName ?? "You").prefix(1)))
                .font(.archivo(28, .bold)).foregroundStyle(Theme.onInverse)
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
                                Text(category.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                                Text(category.detail).font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Divider()
                    }
                    Toggle(isOn: Binding(get: { hidesToday }, set: { hide in Task { await setHideToday(hide) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide today").font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                            Text("Keep today's numbers from \(group.name). Streaks and scores still count.")
                                .font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Invite code").font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
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
            Text(title).font(.app(.subheadline)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}

// MARK: - Tier

/// The tier badge: a two-tone hexagon with rank chevrons.
struct TierHexagon: View {
    let tier: Tier
    var size: CGFloat = 64
    var showsChevrons = true

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 64
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var hexagon = Path()
            hexagon.addLines([point(32, 3), point(57, 17.5), point(57, 46.5), point(32, 61), point(7, 46.5), point(7, 17.5)])
            hexagon.closeSubpath()
            context.fill(hexagon, with: .color(tier.color))
            var right = Path()
            right.addLines([point(32, 3), point(57, 17.5), point(57, 46.5), point(32, 61)])
            right.closeSubpath()
            context.fill(right, with: .color(.black.opacity(0.12)))
            if showsChevrons {
                var chevrons = Path()
                chevrons.addLines([point(20, 31), point(32, 24), point(44, 31)])
                chevrons.move(to: point(20, 41)); chevrons.addLine(to: point(32, 34)); chevrons.addLine(to: point(44, 41))
                context.stroke(chevrons, with: .color(.white), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TierCard: View {
    let tier: TierState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training tier").sectionLabel()
                Spacer()
                (Text("\(tier.consistency)%").font(.archivo(14, .bold)).foregroundStyle(Theme.textPrimary)
                 + Text(" consistency").font(.archivo(14)).foregroundStyle(Theme.textSecondary))
            }
            HStack(spacing: 16) {
                TierHexagon(tier: tier.tier)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tier.tier.title).font(.archivo(48, .semibold, width: 70)).tracking(-0.48).foregroundStyle(Theme.textPrimary)
                        .lineBox(0.85, size: 48)
                    Text(nextLine).font(.archivo(15, .semibold)).foregroundStyle(tier.tier.next == nil ? Theme.textSecondary : Theme.goldText)
                }
            }
            .padding(.top, 16)
            if !tier.isCalibrating {
                TickScale(range: 0...100,
                          minor: .init(divisions: 50, top: 10, height: 16),
                          major: .init(divisions: 10, top: 2, height: 32),
                          fill: Double(tier.consistency), fillColor: Color(light: 0x6E7C86, dark: 0xA3AEB6),
                          bands: tier.tier.next.map { [.init(from: Double(tier.consistency), to: Double($0.minimumConsistency),
                                                             color: Theme.goldTint, top: 10, height: 16)] } ?? [],
                          markers: markers,
                          height: 36, labelRoom: 20,
                          axis: [(0, "0"), (25, "25"), (50, "50"), (75, "75"), (100, "100")])
                    .padding(.top, 16)
            }
            Text(tier.isCalibrating ? "Calibrating: your tier settles after 7 days of data." : "Share of sleep, step, and Effort goals hit over 28 days.")
                .font(.archivo(15)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(1.45, size: 15)
                .padding(.top, 16)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var nextLine: String {
        guard let next = tier.tier.next, let points = tier.pointsToNextTier else { return "The top tier. Hold it." }
        return "\(points) points to \(next.title)"
    }

    private var markers: [TickScale.Marker] {
        var result: [TickScale.Marker] = []
        if let next = tier.tier.next {
            result.append(.init(value: Double(next.minimumConsistency), color: Theme.gold, top: -4, height: 44,
                                label: "\(next.title) \(next.minimumConsistency)%", labelColor: Theme.goldText,
                                labelWeight: .medium, labelPlacement: .trailing))
        }
        result.append(.init(value: Double(tier.consistency), color: Theme.textPrimary, top: -4, height: 44,
                            label: "\(tier.consistency)%", labelColor: Theme.textPrimary, labelWeight: .medium,
                            labelPlacement: .leading))
        return result
    }
}

// MARK: - Badges

struct BadgesSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let earned: [EarnedBadge]
    @State private var selected: BadgeDefinition?
    @State private var showsAll = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let earnedDates = Dictionary(earned.map { ($0.id, $0.earnedOn) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges").sectionHeading()
                Spacer()
                (Text("\(earnedDates.count)").font(.archivo(14, .bold)).foregroundStyle(Theme.textPrimary)
                 + Text(" of \(Badges.all.count)").font(.archivo(14)).foregroundStyle(Theme.textSecondary))
            }
            .padding(.top, 14)
            Text("Milestones in sleep, activity, recovery, and consistency. \(colorScheme == .dark ? "Filled" : "Dark") ones are earned; tap any badge to see what it takes.")
                .font(.archivo(14)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(1.45, size: 14)
                .padding(.top, -4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(showsAll ? Badges.all : Array(Badges.all.prefix(9))) { badge in
                    let isEarned = earnedDates[badge.id] != nil
                    Button { selected = badge } label: {
                        VStack(spacing: 4) {
                            BadgeIcon(badge: badge, isEarned: isEarned, size: 52).padding(.bottom, 8)
                            Text(badge.title)
                                .font(.archivo(14, .bold))
                                .foregroundStyle(isEarned ? Theme.textPrimary : Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(badge.detail)
                                .font(.archivo(12))
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineBox(1.35, size: 12)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .card(padding: EdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8), radius: 22)
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.title), \(isEarned ? "earned" : "locked"): \(badge.detail)")
                    .accessibilityHint("Shows what this badge means")
                }
            }
            Button {
                withAnimation(.snappy) { showsAll.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showsAll ? "Show fewer" : "See all \(Badges.all.count) badges")
                    Image(systemName: showsAll ? "chevron.up" : "chevron.right").font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(.secondary)
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
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(isEarned ? Theme.onInverse : Color(light: 0x7D8B95, dark: 0x6E7F8A))
            .frame(width: size, height: size)
            .background(isEarned ? Theme.inverse : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
            .overlay {
                if !isEarned {
                    RoundedRectangle(cornerRadius: size * 0.35, style: .continuous).strokeBorder(Theme.controlStroke, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let dot = size * 0.385
                Group {
                    if isEarned {
                        Image(systemName: "checkmark").font(.system(size: dot * 0.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: dot, height: dot)
                            .background(Theme.teal, in: Circle())
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    } else {
                        Image(systemName: "lock").font(.system(size: dot * 0.48, weight: .bold)).foregroundStyle(Theme.textMuted)
                            .frame(width: dot, height: dot)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.controlStroke, lineWidth: 1.5))
                    }
                }
                .offset(x: 4, y: 4)
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
                Text(badge.title).font(.app(.title2, .bold)).foregroundStyle(Theme.textPrimary)
                Label(earnedOn.map { "Earned \($0.noon.formatted(.dateTime.month(.wide).day().year()))" } ?? "Not earned yet",
                      systemImage: earnedOn == nil ? "lock.fill" : "checkmark.seal.fill")
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(earnedOn == nil ? Theme.textSecondary : Theme.gold)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to earn it").sectionLabel()
                    Text(badge.detail + ".").font(.app(.body)).foregroundStyle(Theme.textPrimary)
                }
                if !badge.why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters").sectionLabel()
                        Text(badge.why).font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
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
