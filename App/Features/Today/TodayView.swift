import SwiftUI

/// The morning view: Recovery front and center, then Sleep, Effort and today's
/// target, streaks, and this week's challenges.
struct TodayView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private var health: HealthModel { session.health }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                banners
                RecoveryCard(scores: health.todayScores, record: health.todayRecord,
                             nightsCollected: health.snapshot.hrvNightsCollected)
                HStack(spacing: 12) {
                    SleepCard(scores: health.todayScores, record: health.todayRecord, goals: health.goals)
                    EffortCard(scores: health.todayScores)
                }
                EffortTargetCard(scores: health.todayScores, record: health.todayRecord)
                StreaksRow(streaks: health.snapshot.streaks)
                ChallengesSection(challenges: health.snapshot.challenges, group: health.snapshot.groupChallenge) {
                    session.selectedTab = .team
                }
                if health.hasData {
                    ShareWeekButton(recap: WeeklyRecap.make(snapshot: health.snapshot, records: health.records,
                                                            weekStart: health.today.weekStart))
                }
                Text("Scores are estimates to guide training, not medical advice.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .refreshable { await session.refresh() }
        .sensoryFeedback(.success, trigger: health.promotion) { _, new in new != nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.dayTitle(health.today)).sectionLabel()
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                Spacer()
                if health.isSyncing { ProgressView() }
            }
            if let device = health.device {
                Label(deviceLine(device), systemImage: "applewatch.side.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func deviceLine(_ device: DeviceStatus) -> String {
        var parts = [device.name]
        if let lastSync = device.lastSync { parts.append("synced \(Format.ago(lastSync))") }
        if let battery = device.batteryPercent { parts.append("\(battery)%") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var banners: some View {
        if let tier = health.promotion {
            Banner(symbol: "shield.fill", message: "Promoted to \(tier.title)! Four weeks of consistency earned it.",
                   color: tier.color, actionTitle: "Nice") {
                health.promotion = nil
            }
        }
        if health.needsReconnect {
            Banner(symbol: "link.badge.plus", message: "Your Fitbit connection expired.", color: Theme.recoveryRest,
                   actionTitle: "Reconnect") {
                Task {
                    await session.reconnectGoogle { url, scheme in
                        try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: scheme)
                    }
                }
            }
        } else if let problem = health.syncProblem {
            Banner(symbol: "wifi.exclamationmark", message: problem)
        }
        if !health.state.missingCategories.isEmpty {
            Banner(symbol: "exclamationmark.lock",
                   message: "Missing access to \(health.state.missingCategories.sorted().map(\.title).joined(separator: ", ")). Sign out and back in to grant it.")
        }
        if !health.hasData && !health.isSyncing {
            Banner(symbol: "moon.zzz", message: "No data yet. Wear your Fitbit Air tonight and sync it in the Google Health app.",
                   color: Theme.sleep)
        }
    }
}

// MARK: - Recovery

struct RecoveryCard: View {
    let scores: DayScores?
    let record: DayRecord?
    let nightsCollected: Int

    var body: some View {
        VStack(spacing: 16) {
            switch scores?.recovery ?? .calibrating(nightsCollected: nightsCollected) {
            case .scored(let recovery):
                ScoreDial(value: recovery.total, color: recovery.band.color, size: 210, label: "Recovery")
                VStack(spacing: 4) {
                    Text(recovery.band.title.uppercased())
                        .font(.headline.weight(.heavy)).tracking(2)
                        .foregroundStyle(recovery.band.color)
                    Text(recovery.band.advice)
                        .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
            case .calibrating(let nights):
                ScoreDial(value: nil, color: Theme.textSecondary, size: 210, label: "Calibrating",
                          placeholder: "\(min(nights, ScoreTuning.baselineMinimumNights))/\(ScoreTuning.baselineMinimumNights)")
                Text("Recovery unlocks after \(ScoreTuning.baselineMinimumNights) nights of HRV. Keep wearing your Fitbit Air to bed.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            case .unavailable:
                ScoreDial(value: nil, color: Theme.textSecondary, size: 210, label: "Recovery")
                Text("No HRV from last night yet. It appears after your Fitbit Air syncs in the morning.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            HStack {
                StatPill(title: "HRV", value: record?.hrvMs.map { "\(Int($0.rounded())) ms" } ?? "—")
                StatPill(title: "Resting HR", value: record?.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
                StatPill(title: "Sleep", value: record?.sleep.map { Format.duration(minutes: $0.minutesAsleep) } ?? "—")
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Sleep and Effort

struct SleepCard: View {
    let scores: DayScores?
    let record: DayRecord?
    let goals: Goals

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep").sectionLabel()
            ScoreDial(value: scores?.sleep?.total, color: Theme.sleep, size: 96, lineWidth: 10)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(record?.sleep.map { Format.duration(minutes: $0.minutesAsleep) } ?? "No sleep data")
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Goal \(Format.duration(minutes: goals.sleepMinutes))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

struct EffortCard: View {
    let scores: DayScores?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effort").sectionLabel()
            ScoreDial(value: scores?.effort, color: Theme.effort, size: 96, lineWidth: 10)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(scores.map { "Target \($0.effortTarget.lowerBound)–\($0.effortTarget.upperBound)" } ?? "Target —")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private var statusText: String {
        guard let scores, let effort = scores.effort else { return "Not started" }
        switch Effort.status(score: effort, target: scores.effortTarget) {
        case .below: return "Building"
        case .onTarget: return "On target"
        case .above: return "Above target"
        }
    }
}

struct EffortTargetCard: View {
    let scores: DayScores?
    let record: DayRecord?

    var body: some View {
        if let scores {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today's Effort target").sectionLabel()
                    Spacer()
                    Text("\(scores.effortTarget.lowerBound)–\(scores.effortTarget.upperBound)")
                        .font(.headline).monospacedDigit().foregroundStyle(Theme.effort)
                }
                EffortTrack(effort: scores.effort, target: scores.effortTarget)
                Text(coaching(scores))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    private func coaching(_ scores: DayScores) -> String {
        let minutes = record?.activeZoneMinutes ?? 0
        let needed = Effort.activeZoneMinutes(forScore: scores.effortTarget.lowerBound)
        let effort = scores.effort ?? 0
        switch Effort.status(score: effort, target: scores.effortTarget) {
        case .below:
            return "\(minutes) Active Zone Minutes so far. About \(max(0, needed - minutes)) more to reach your target."
        case .onTarget:
            return "On target with \(minutes) Active Zone Minutes. Nice work."
        case .above:
            return scores.recovery.score?.band == .recover
                ? "Above target on a Recover day. Ease off and let your body bounce back."
                : "Above target with \(minutes) Active Zone Minutes. Bonus work, but recover well tonight."
        }
    }
}

// MARK: - Streaks

struct StreaksRow: View {
    let streaks: [StreakKind: StreakState]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Streaks")
            HStack(spacing: 10) {
                ForEach(StreakKind.allCases, id: \.self) { kind in
                    chip(kind, streaks[kind] ?? StreakState())
                }
            }
        }
    }

    private func chip(_ kind: StreakKind, _ state: StreakState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(state.current > 0 ? Theme.recoverySteady : Theme.textSecondary)
                Text("\(state.current)").font(.scoreNumber(24)).foregroundStyle(Theme.textPrimary)
            }
            Text(shortTitle(kind)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 2) {
                ForEach(0..<ScoreTuning.maxRestTokens, id: \.self) { index in
                    Image(systemName: index < state.restTokens ? "shield.fill" : "shield")
                        .font(.caption2)
                        .foregroundStyle(index < state.restTokens ? Theme.effort : Theme.hairline)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) streak: \(state.current) days, \(state.restTokens) rest tokens")
    }

    private func shortTitle(_ kind: StreakKind) -> String {
        switch kind {
        case .sleep: "Sleep goal"
        case .steps: "Step goal"
        case .effort: "On target"
        }
    }
}

// MARK: - Challenges

struct ChallengesSection: View {
    let challenges: [Challenge]
    let group: GroupChallengeKind
    let openTeam: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("This week", trailing: "Resets Monday")
            VStack(spacing: 14) {
                ForEach(challenges) { challenge in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: challenge.isComplete ? "checkmark.seal.fill" : "target")
                                .foregroundStyle(challenge.isComplete ? Theme.recoveryGo : Theme.effort)
                            Text(challenge.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text("\(Format.count(challenge.progress))/\(Format.count(challenge.target))")
                                .font(.caption).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                        ProgressBar(fraction: challenge.fraction, color: challenge.isComplete ? Theme.recoveryGo : Theme.effort)
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider()
                Button(action: openTeam) {
                    HStack {
                        Image(systemName: "person.3.fill").foregroundStyle(Theme.effort)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Group challenge").font(.caption).foregroundStyle(Theme.textSecondary)
                            Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }
}
