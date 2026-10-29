import SwiftUI

/// The group challenge, the weekly leaderboard, and everyone's day.
struct TeamView: View {
    @Environment(AppSession.self) private var session
    @State private var showingChallenges = false

    private var team: TeamModel { session.team }
    private var today: CivilDate { session.health.today }

    var body: some View {
        PlutoScreen(title: "Team", subtitle: team.selectedGroup?.name ?? "Your crew",
                    startsAtBottom: session.options.startsAtBottom, refresh: { await session.refresh() }) {
            header
            if let code = session.pendingInviteCode {
                JoinInviteBanner(code: code)
            }
            if let error = team.errorMessage {
                Banner(symbol: "exclamationmark.triangle", message: error, color: Theme.effort)
            }
            if team.selectedGroup == nil {
                if team.hasLoaded { NoGroupCard() }
            } else {
                GroupChallengeCard(challenge: session.health.snapshot.groupChallenge) { showingChallenges = true }
                    .padding(.top, 6)
                LeaderboardSection()
                SectionTitle("Today", trailing: DayFormat.eyebrow(today))
                ForEach(team.cards(on: today)) { card in
                    FriendCardView(card: card, groupName: team.selectedGroup?.name ?? "")
                }
                Text("Recovery, HRV, and resting heart rate show on cards but are never ranked.")
                    .font(.archivo(12)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingChallenges) {
            ChallengesSheet(group: session.health.snapshot.groupChallenge, challenges: session.health.snapshot.challenges)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if team.groups.count > 1 {
                    Menu {
                        ForEach(team.groups) { group in
                            Button(group.name) {
                                team.selectedGroupID = group.id
                                Task { await team.refresh(today: today) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(team.selectedGroup?.name ?? "").eyebrow()
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
                        }
                    }
                } else {
                    Text(team.selectedGroup?.name ?? "Your crew").eyebrow()
                }
                Text("Team").screenTitle()
            }
            Spacer()
            if let group = team.selectedGroup {
                ShareLink(item: InviteText.message(for: group)) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.controlStroke, lineWidth: 1))
                }
                .accessibilityLabel("Invite a teammate")
            }
        }
    }
}

/// The text shared when inviting someone.
enum InviteText {
    static func message(for group: GroupInfo) -> String {
        let scheme = (Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String) ?? "connector"
        return "Join my group \"\(group.name)\" on Pluto and let's train together. Code: \(group.inviteCode)\n\(scheme)://join/\(group.inviteCode)"
    }
}

// MARK: - Group challenge

struct GroupChallengeCard: View {
    let challenge: GroupChallengeKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "trophy")
                    .font(.system(size: 21))
                    .foregroundStyle(Color(hex: 0xFF9D66))
                    .frame(width: 48, height: 48)
                    .background(Color(light: 0x273841, dark: 0x3A2418), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Group challenge").font(.mono(11)).tracking(1.1).textCase(.uppercase)
                        .foregroundStyle(Color(light: 0xA9B7C0, dark: 0x8696A1))
                    Text(challenge.title).font(.archivo(20, .bold)).foregroundStyle(Color(light: 0xFFFFFF, dark: 0xEEF2F4))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineBox(1.1, size: 20)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(light: 0xA9B7C0, dark: 0x8696A1))
            }
            .padding(16)
            .background(Color(light: 0x0C1B26, dark: 0x1A2831), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(light: 0x0C1B26, dark: 0x2A3943), lineWidth: 1))
        }
        .buttonStyle(.pressableCard)
        .accessibilityHint("Shows this week's challenges")
    }
}

struct ChallengesSheet: View {
    let group: GroupChallengeKind
    let challenges: [Challenge]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("This week").eyebrow().padding(.top, 24)
                Text(group.title).screenTitle(32)
                Text("Your group competes on this all week; the leaderboard below it tracks the race. It resets Monday.")
                    .font(.archivo(15)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SectionTitle("Your challenges", trailing: "Resets Monday")
                ChallengesSection(challenges: challenges)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Leaderboard

struct LeaderboardSection: View {
    @Environment(AppSession.self) private var session

    private var team: TeamModel { session.team }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Leaderboard", trailing: "This week")
            VStack(alignment: .leading, spacing: 0) {
                tabs
                if team.leaderboard.isEmpty {
                    Text("No shared numbers yet this week.")
                        .font(.archivo(15)).foregroundStyle(Theme.textSecondary)
                        .padding(14)
                } else {
                    let best = max(1, team.leaderboard.map(\.value).max() ?? 1)
                    VStack(spacing: 2) {
                        ForEach(team.leaderboard) { entry in
                            row(entry, fraction: entry.value / best)
                        }
                    }
                }
            }
            .card(padding: EdgeInsets(top: 6, leading: 12, bottom: 12, trailing: 12))
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardMetric.allCases) { metric in
                let selected = team.leaderboardMetric == metric
                Button {
                    team.leaderboardMetric = metric
                    Task { await team.loadLeaderboard(today: session.health.today) }
                } label: {
                    Text(metric.title)
                        .font(.archivo(14, selected ? .bold : .medium))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? Theme.textPrimary : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func row(_ entry: LeaderboardEntry, fraction: Double) -> some View {
        let isYou = entry.userID == team.myID
        return HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.mono(13, .medium))
                .foregroundStyle(entry.rank == 1 ? Theme.effort : Theme.textSecondary)
                .frame(width: 16, alignment: .leading)
            AvatarView(name: isYou ? "You" : entry.displayName, url: entry.avatarURL.flatMap(URL.init(string:)), size: 38,
                       highlighted: isYou)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isYou ? "You" : entry.displayName)
                        .font(.archivo(16, isYou ? .bold : .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.leaderboard(entry.value, metric: team.leaderboardMetric))
                        .font(.archivo(22, .semibold, width: 72))
                        .foregroundStyle(isYou ? Theme.teal : Theme.textPrimary)
                        .lineBox(1, size: 22)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(isYou ? Theme.tealTrack : Color(light: 0xEDF0F2, dark: 0x1E2C36))
                        Capsule().fill(isYou ? Theme.teal : Color(light: 0xB4BFC6, dark: 0x4C5D68))
                            .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(10)
        .background(isYou ? Theme.tealRow : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day cards

struct FriendCardView: View {
    let card: FriendCard
    var groupName: String = ""
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AvatarView(name: card.isYou ? "You" : card.member.profile.displayName, url: card.member.profile.avatarURL,
                           size: 44, highlighted: card.isYou)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.isYou ? "You" : card.member.profile.displayName)
                        .font(.archivo(17, .bold)).foregroundStyle(Theme.textPrimary)
                    Text(card.hasData ? subtitle : "Not synced yet today")
                        .font(.archivo(14)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                recoveryBadge
            }
            if card.hasData {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, 16).padding(.bottom, 14)
                HStack(alignment: .top, spacing: 12) {
                    stat("Sleep", card.sleepScore.map(String.init), Theme.sleep)
                    stat("Effort", card.effort.map(String.init), Theme.effort)
                    stat("Steps", card.steps.map(Format.count), Theme.textPrimary)
                }
            }
            reactionsRow.padding(.top, 16)
        }
        .card(padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
    }

    private var subtitle: String {
        card.sleepMinutes.map { "Slept \(Format.duration(minutes: $0))" } ?? "Synced today"
    }

    private func stat(_ title: String, _ value: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundStyle(Theme.textMuted)
            Text(value ?? "—").font(.archivo(28, .semibold, width: 72))
                .foregroundStyle(value == nil ? Theme.textFaint : color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .lineBox(1, size: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var recoveryBadge: some View {
        if let recovery = card.recovery, let band = card.recoveryBand {
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(recovery)").font(.scoreNumber(36)).foregroundStyle(band.color).lineBox(0.85, size: 36)
                Text(band.title).font(.mono(10)).tracking(1).textCase(.uppercase).foregroundStyle(band.textColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recovery \(recovery), \(band.title)")
        } else if card.hasData {
            Image(systemName: "lock")
                .foregroundStyle(Theme.textMuted)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceRaised, in: Circle())
                .accessibilityLabel("Recovery not shared")
        }
    }

    private var reactionsRow: some View {
        HStack(spacing: 8) {
            ForEach(card.reactions) { reaction in
                Button {
                    Task { await session.team.toggleReaction(reaction.emoji, on: card) }
                } label: {
                    HStack(spacing: 8) {
                        Text(reaction.emoji).font(.system(size: 17))
                        Text("\(reaction.count)").font(.archivo(15, .bold))
                    }
                    .padding(.leading, 12).padding(.trailing, 16).frame(height: 44)
                    .background(reaction.mine != nil ? Theme.tealTint : Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(reaction.mine != nil ? Theme.teal : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("\(reaction.emoji) \(reaction.count)\(reaction.mine != nil ? ", including yours" : "")")
            }
            if !card.isYou {
                Menu {
                    ForEach(Reaction.choices, id: \.self) { emoji in
                        Button(emoji) { Task { await session.team.toggleReaction(emoji, on: card) } }
                    }
                } label: {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .accessibilityLabel("React to \(card.member.profile.displayName)'s day")
            }
            Spacer(minLength: 8)
            if !groupName.isEmpty {
                Text("Shared with \(groupName)").font(.archivo(13)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: card.reactions.map(\.count))
    }
}

// MARK: - Joining

/// Shown after opening an invite link.
struct JoinInviteBanner: View {
    let code: String
    @Environment(AppSession.self) private var session
    @State private var isJoining = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.open.fill").foregroundStyle(Theme.effort).font(.app(.title3))
            VStack(alignment: .leading, spacing: 2) {
                Text("You're invited").font(.app(.headline)).foregroundStyle(Theme.textPrimary)
                Text("Code \(code)").font(.app(.caption)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Join") {
                isJoining = true
                Task {
                    _ = try? await session.team.joinGroup(code: code, today: session.health.today)
                    session.pendingInviteCode = nil
                    isJoining = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining)
            Button {
                session.pendingInviteCode = nil
            } label: {
                Image(systemName: "xmark").foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .card()
    }
}

/// When you're not in a group yet.
struct NoGroupCard: View {
    @Environment(AppSession.self) private var session
    @State private var code = ""
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.3.fill").font(.app(.largeTitle)).foregroundStyle(Theme.effort)
            Text("Train with friends").font(.app(.title2, .bold)).foregroundStyle(Theme.textPrimary)
            Text("Join a group with an invite code, or start one and invite your crew.")
                .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            Button("Join group") { run { try await session.team.joinGroup(code: code, today: session.health.today) } }
                .buttonStyle(.primary)
                .disabled(!InviteCode.isComplete(code))
            TextField("New group name", text: $name)
                .padding(12)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            Button("Create group") { run { try await session.team.createGroup(named: name, today: session.health.today) } }
                .buttonStyle(.secondary)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            if let error {
                Text(error).font(.app(.footnote)).foregroundStyle(Theme.recoveryRest)
            }
        }
        .card()
    }

    private func run(_ work: @escaping () async throws -> GroupInfo) {
        Task {
            do {
                _ = try await work()
                error = nil
            } catch {
                self.error = OnboardingModel.message(for: error)
            }
        }
    }
}
