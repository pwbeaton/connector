import Foundation
import Observation

/// Your groups and what your friends share with them: day cards, reactions,
/// leaderboards, and your own sharing settings.
@Observable
final class TeamModel {
    private(set) var groups: [GroupInfo] = []
    var selectedGroupID: UUID?
    private(set) var members: [Member] = []
    private(set) var feed: [FriendMetric] = []
    private(set) var reactions: [Reaction] = []
    private(set) var leaderboard: [LeaderboardEntry] = []
    var leaderboardMetric: LeaderboardMetric = .steps
    private(set) var mySharing: [SharingSetting] = []
    private(set) var myID: UUID?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    var selectedGroup: GroupInfo? { groups.first { $0.id == selectedGroupID } ?? groups.first }

    func cards(on day: CivilDate) -> [FriendCard] {
        FriendCard.build(members: members, feed: feed, reactions: reactions, day: day, me: myID)
    }

    func isSharing(_ category: SharingCategory) -> Bool {
        mySharing.first { $0.category == category }?.enabled ?? false
    }

    func isHidden(_ category: SharingCategory, on day: CivilDate) -> Bool {
        mySharing.first { $0.category == category }?.hiddenDates.contains(day) ?? false
    }

    // MARK: Loading

    /// Reloads groups and everything about the selected one.
    func refresh(today: CivilDate) async {
        isLoading = true
        defer { isLoading = false }
        do {
            myID = await services.backend.currentUserID()
            groups = try await services.backend.myGroups()
            if selectedGroupID == nil || !groups.contains(where: { $0.id == selectedGroupID }) {
                selectedGroupID = groups.first?.id
            }
            guard let group = selectedGroup else {
                members = []; feed = []; reactions = []; leaderboard = []; mySharing = []
                hasLoaded = true
                return
            }
            let backend = services.backend
            async let members = backend.members(of: group.id)
            async let feed = backend.feed(groupID: group.id, from: today.adding(days: -6), through: today)
            async let reactions = backend.reactions(groupID: group.id, from: today.adding(days: -1), through: today)
            async let sharing = backend.sharing(in: group.id)
            (self.members, self.feed, self.reactions, self.mySharing) = try await (members, feed, reactions, sharing)
            await loadLeaderboard(today: today)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your team. Pull to try again."
        }
        hasLoaded = true
    }

    func loadLeaderboard(today: CivilDate) async {
        guard let group = selectedGroup else { return }
        do {
            leaderboard = try await services.backend.leaderboard(groupID: group.id, weekStart: today.weekStart,
                                                                metric: leaderboardMetric)
        } catch {
            leaderboard = []
        }
    }

    // MARK: Groups

    func createGroup(named name: String, today: CivilDate) async throws -> GroupInfo {
        let group = try await services.backend.createGroup(named: name)
        try await shareEverything(with: group)
        selectedGroupID = group.id
        await refresh(today: today)
        return group
    }

    func joinGroup(code: String, today: CivilDate) async throws -> GroupInfo {
        let group = try await services.backend.joinGroup(code: InviteCode.normalize(code))
        try await shareEverything(with: group)
        selectedGroupID = group.id
        await refresh(today: today)
        return group
    }

    func leave(_ group: GroupInfo, today: CivilDate) async {
        try? await services.backend.leaveGroup(group.id)
        selectedGroupID = nil
        await refresh(today: today)
    }

    /// New groups start with everything shared (one tap to continue); change it any time.
    private func shareEverything(with group: GroupInfo) async throws {
        guard let me = await services.backend.currentUserID() else { throw BackendError.notSignedIn }
        try await services.backend.saveSharing(SharingSetting.shareAll(userID: me, groupID: group.id))
    }

    // MARK: Sharing

    func setSharing(_ category: SharingCategory, enabled: Bool, today: CivilDate) async {
        await changeSetting(category, today: today) { $0.enabled = enabled }
    }

    func setHidden(_ category: SharingCategory, on day: CivilDate, hidden: Bool, today: CivilDate) async {
        await changeSetting(category, today: today) { setting in
            setting.hiddenDates.removeAll { $0 == day }
            if hidden { setting.hiddenDates.append(day) }
        }
    }

    private func changeSetting(_ category: SharingCategory, today: CivilDate,
                               change: (inout SharingSetting) -> Void) async {
        guard let group = selectedGroup, let me = myID else { return }
        var setting = mySharing.first { $0.category == category }
            ?? SharingSetting(userID: me, groupID: group.id, category: category, enabled: false)
        change(&setting)
        // Show the change right away; the server confirms on refresh.
        mySharing.removeAll { $0.category == category }
        mySharing.append(setting)
        do {
            try await services.backend.saveSharing([setting])
        } catch {
            errorMessage = "Couldn't save that change. Check your connection."
        }
        await refresh(today: today)
    }

    // MARK: Reactions

    func toggleReaction(_ emoji: String, on card: FriendCard) async {
        guard let group = selectedGroup else { return }
        do {
            if let mine = reactions.first(where: {
                $0.ownerID == card.member.id && $0.day == card.day && $0.emoji == emoji && $0.authorID == myID
            }) {
                reactions.removeAll { $0.id == mine.id }
                try await services.backend.removeReaction(id: mine.id)
            } else {
                let reaction = try await services.backend.addReaction(groupID: group.id, ownerID: card.member.id,
                                                                      day: card.day, emoji: emoji)
                reactions.append(reaction)
            }
        } catch {
            errorMessage = "Couldn't send that reaction."
        }
    }
}
