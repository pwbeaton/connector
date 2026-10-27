import Foundation

/// One person's day as the Team tab shows it. Nil values mean "not shared or not
/// synced yet", never zero.
nonisolated struct FriendCard: Identifiable, Equatable, Sendable {
    nonisolated struct ReactionCount: Equatable, Sendable, Identifiable {
        let emoji: String
        let count: Int
        /// Your own reaction, so tapping again takes it back.
        let mine: Reaction?

        var id: String { emoji }
    }

    let member: Member
    let day: CivilDate
    let isYou: Bool
    var recovery: Int?
    var sleepScore: Int?
    var sleepMinutes: Int?
    var effort: Int?
    var steps: Int?
    var activeZoneMinutes: Int?
    var reactions: [ReactionCount] = []

    var id: UUID { member.id }
    var hasData: Bool { [recovery, sleepScore, sleepMinutes, effort, steps].contains { $0 != nil } }
    var recoveryBand: RecoveryBand? { recovery.map(RecoveryBand.init(score:)) }

    /// Cards for every member on `day`: you first, then everyone else by name.
    static func build(members: [Member], feed: [FriendMetric], reactions: [Reaction], day: CivilDate,
                      me: UUID?) -> [FriendCard] {
        let rows = Dictionary(grouping: feed.filter { $0.date == day }, by: \.userID)
        return members.map { member in
            let values = Dictionary((rows[member.id] ?? []).map { ($0.metric, $0.value) }, uniquingKeysWith: { $1 })
            func int(_ metric: Metric) -> Int? { values[metric].map { Int($0.rounded()) } }

            let theirs = reactions.filter { $0.ownerID == member.id && $0.day == day }
            let counts = Reaction.choices.compactMap { emoji -> ReactionCount? in
                let matching = theirs.filter { $0.emoji == emoji }
                guard !matching.isEmpty else { return nil }
                return ReactionCount(emoji: emoji, count: matching.count, mine: matching.first { $0.authorID == me })
            }
            return FriendCard(member: member, day: day, isYou: member.id == me,
                              recovery: int(.recoveryScore), sleepScore: int(.sleepScore), sleepMinutes: int(.sleepMinutes),
                              effort: int(.effortScore), steps: int(.steps), activeZoneMinutes: int(.azm),
                              reactions: counts)
        }
        .sorted { lhs, rhs in
            if lhs.isYou != rhs.isYou { return lhs.isYou }
            return lhs.member.profile.displayName.localizedCaseInsensitiveCompare(rhs.member.profile.displayName)
                == .orderedAscending
        }
    }
}
