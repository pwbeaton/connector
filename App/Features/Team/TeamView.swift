import SwiftUI

/// Friends' day cards, reactions, the weekly group challenge, and leaderboards.
struct TeamView: View {
    @Environment(AppSession.self) private var session

    private var team: TeamModel { session.team }
    private var today: CivilDate { session.health.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let code = session.pendingInviteCode {
                    JoinInviteBanner(code: code)
                }
                if let error = team.errorMessage {
                    Banner(symbol: "exclamationmark.triangle", message: error)
                }
                if team.selectedGroup == nil {
                    if team.hasLoaded { NoGroupCard() }
                } else {
                    LeaderboardSection(groupChallenge: session.health.snapshot.groupChallenge)
                    SectionTitle("Today", trailing: Format.dayTitle(today))
                    ForEach(team.cards(on: today)) { card in
                        FriendCardView(card: card)
                    }
                    Text("Recovery, HRV, and resting heart rate show on cards but are never ranked.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .refreshable { await session.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
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
                            Text(team.selectedGroup?.name ?? "").sectionLabel()
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else {
                    Text(team.selectedGroup?.name ?? "Your crew").sectionLabel()
                }
                Text("Team").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let group = team.selectedGroup {
                ShareLink(item: InviteText.message(for: group)) {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Invite friends")
            }
        }
    }
}

/// The text shared when inviting someone.
enum InviteText {
    static func message(for group: GroupInfo) -> String {
        let scheme = (Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String) ?? "connector"
        return "Join my group \"\(group.name)\" and let's train together. Code: \(group.inviteCode)\n\(scheme)://join/\(group.inviteCode)"
    }
}

// MARK: - Leaderboard

struct LeaderboardSection: View {
    let groupChallenge: GroupChallengeKind
    @Environment(AppSession.self) private var session

    private var team: TeamModel { session.team }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Leaderboard", trailing: "This week")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                    Text("Group challenge: \(groupChallenge.title)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                }
                Picker("Metric", selection: Binding(get: { team.leaderboardMetric },
                                                    set: { team.leaderboardMetric = $0 })) {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: team.leaderboardMetric) {
                    Task { await team.loadLeaderboard(today: session.health.today) }
                }
                if team.leaderboard.isEmpty {
                    Text("No shared numbers yet this week.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(team.leaderboard) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func row(_ entry: LeaderboardEntry) -> some View {
        let isYou = entry.userID == team.myID
        return HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.scoreNumber(18))
                .foregroundStyle(entry.rank == 1 ? Theme.gold : Theme.textSecondary)
                .frame(width: 24)
            AvatarView(name: entry.displayName, url: entry.avatarURL.flatMap(URL.init(string:)), size: 32)
            Text(isYou ? "You" : entry.displayName)
                .font(.subheadline.weight(isYou ? .bold : .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(Format.leaderboard(entry.value, metric: team.leaderboardMetric))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(isYou ? Theme.effort : Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day cards

struct FriendCardView: View {
    let card: FriendCard
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(name: card.member.profile.displayName, url: card.member.profile.avatarURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.isYou ? "You" : card.member.profile.displayName)
                        .font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(card.hasData ? subtitle : "Not synced yet today")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                recoveryBadge
            }
            if card.hasData {
                HStack {
                    StatPill(title: "Sleep", value: card.sleepScore.map(String.init) ?? "—", color: Theme.sleep)
                    StatPill(title: "Effort", value: card.effort.map(String.init) ?? "—", color: Theme.effort)
                    StatPill(title: "Steps", value: card.steps.map(Format.count) ?? "—")
                }
            }
            reactionsRow
        }
        .card()
    }

    private var subtitle: String {
        card.sleepMinutes.map { "Slept \(Format.duration(minutes: $0))" } ?? "Synced today"
    }

    @ViewBuilder private var recoveryBadge: some View {
        if let recovery = card.recovery, let band = card.recoveryBand {
            VStack(spacing: 0) {
                Text("\(recovery)").font(.scoreNumber(22)).foregroundStyle(band.color)
                Text(band.title.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(band.color)
            }
            .frame(width: 64, height: 48)
            .background(band.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recovery \(recovery), \(band.title)")
        } else if card.hasData {
            Image(systemName: "lock.fill")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, height: 48)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Recovery not shared")
        }
    }

    private var reactionsRow: some View {
        HStack(spacing: 8) {
            ForEach(card.reactions) { reaction in
                Button {
                    Task { await session.team.toggleReaction(reaction.emoji, on: card) }
                } label: {
                    Text("\(reaction.emoji) \(reaction.count)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background(reaction.mine != nil ? Theme.effort.opacity(0.18) : Theme.surfaceRaised,
                                    in: Capsule())
                        .overlay(Capsule().stroke(reaction.mine != nil ? Theme.effort : .clear, lineWidth: 1))
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
                    Image(systemName: "face.smiling")
                        .font(.subheadline)
                        .frame(width: 44, height: 32)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
                .accessibilityLabel("React to \(card.member.profile.displayName)'s day")
            }
            Spacer(minLength: 0)
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
            Image(systemName: "envelope.open.fill").foregroundStyle(Theme.effort).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're invited").font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Code \(code)").font(.caption).foregroundStyle(Theme.textSecondary)
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
            Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(Theme.effort)
            Text("Train with friends").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            Text("Join a group with an invite code, or start one and invite your crew.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
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
                Text(error).font(.footnote).foregroundStyle(Theme.recoveryRest)
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
