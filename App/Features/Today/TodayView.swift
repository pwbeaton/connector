import SwiftUI

/// What a tap on Today opens.
enum TodayDetail: Identifiable, Hashable {
    case score(ScoreKind, CivilDate)
    case biologicalAge(CivilDate)

    var id: String {
        switch self {
        case .score(let kind, let date): "\(kind.rawValue)-\(date)"
        case .biologicalAge(let date): "age-\(date)"
        }
    }
}

/// The morning view: Recovery front and center, then Sleep, Effort and today's
/// target, streaks, this week's challenges, and biological age.
/// Swipe right to page back through earlier days.
struct TodayView: View {
    @Environment(AppSession.self) private var session
    @State private var selectedDate: CivilDate?
    @State private var detail: TodayDetail?
    /// Hides the "swipe for earlier days" hint once you've found it.
    @AppStorage("hasBrowsedDays") private var hasBrowsedDays = false

    private var health: HealthModel { session.health }

    var body: some View {
        let dates = health.browsableDates
        let current = selectedDate.flatMap { dates.contains($0) ? $0 : nil } ?? health.today
        TabView(selection: Binding(get: { current }, set: { selectedDate = $0 })) {
            ForEach(dates, id: \.self) { date in
                DayPage(date: date,
                        canGoBack: date > (dates.first ?? date),
                        showsSwipeHint: !hasBrowsedDays && dates.count > 1,
                        move: { days in move(by: days, from: date, within: dates) },
                        showDetail: { detail = $0 })
                    .tag(date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectedDate)
        .sensoryFeedback(.success, trigger: health.promotion) { _, new in new != nil }
        .onChange(of: selectedDate) { _, new in
            if let new, new != health.today { hasBrowsedDays = true }
        }
        .onChange(of: health.today) { selectedDate = nil }
        .sheet(item: $detail) { detail in
            Group {
                switch detail {
                case .score(let kind, let date): ScoreDetailView(kind: kind, date: date)
                case .biologicalAge(let date): BiologicalAgeDetailView(date: date)
                }
            }
            .environment(session)
        }
    }

    private func move(by days: Int, from date: CivilDate, within dates: [CivilDate]) {
        let target = date.adding(days: days)
        guard dates.contains(target) else { return }
        withAnimation(.snappy) { selectedDate = target }
    }
}

/// One day of stats. Today also shows banners, streaks, and challenges.
struct DayPage: View {
    @Environment(AppSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.exitSampleData) private var exitSampleData

    let date: CivilDate
    let canGoBack: Bool
    let showsSwipeHint: Bool
    let move: (Int) -> Void
    let showDetail: (TodayDetail) -> Void

    private var health: HealthModel { session.health }
    private var isToday: Bool { date == health.today }
    private var scores: DayScores? { health.scores(on: date) }
    private var record: DayRecord? { health.record(on: date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isToday { banners }
                Button { showDetail(.score(.recovery, date)) } label: {
                    RecoveryCard(scores: scores, record: record, nightsCollected: nightsCollected,
                                 change: health.dayChange(.recovery, on: date))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Shows your Recovery history")
                HStack(alignment: .top, spacing: 12) {
                    Button { showDetail(.score(.sleep, date)) } label: {
                        SleepCard(scores: scores, record: record, goals: health.goals,
                                  change: health.dayChange(.sleep, on: date))
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityHint("Shows your Sleep history")
                    Button { showDetail(.score(.effort, date)) } label: {
                        EffortCard(scores: scores, isToday: isToday, change: health.dayChange(.effort, on: date),
                                   yesterday: health.scores(on: date.adding(days: -1))?.effort)
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityHint("Shows your Effort history")
                }
                .fixedSize(horizontal: false, vertical: true)
                Button { showDetail(.biologicalAge(date)) } label: {
                    BiologicalAgeCard(result: health.biologicalAge(on: date), trend: health.biologicalAgeTrend(on: date),
                                      history: biologicalAgeHistory, hasAge: health.chronologicalAge != nil,
                                      daysOfData: daysOfData)
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Shows what moves your biological age")
                if isToday, let plan = health.bedtimePlan(on: date) {
                    Button { showDetail(.score(.sleep, date)) } label: {
                        TonightCard(plan: plan, debt: health.sleepDebt(on: date))
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityHint("Shows your sleep debt and sleep history")
                }
                EffortTargetCard(scores: scores, record: record, isToday: isToday)
                if isToday {
                    StreaksRow(streaks: health.snapshot.streaks)
                    ChallengesSection(challenges: health.snapshot.challenges, group: health.snapshot.groupChallenge) {
                        session.selectedTab = .team
                    }
                }
                if isToday && health.hasData {
                    ShareWeekButton(recap: WeeklyRecap.make(snapshot: health.snapshot, records: health.records,
                                                            weekStart: health.today.weekStart))
                }
                Text("Scores are estimates to guide training, not medical advice.")
                    .font(.app(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(Theme.screenPadding)
        }
        .defaultScrollAnchor(isToday && session.options.startsAtBottom ? .bottom : .top)
        .refreshable { await session.refresh() }
    }

    private var nightsCollected: Int {
        isToday ? health.snapshot.hrvNightsCollected
            : Baselines.nightsCollected(before: date.adding(days: 1), in: health.records) { $0.hrvMs }
    }

    private var daysOfData: Int {
        health.records.filter { $0.date <= date && $0.date > date.adding(days: -BiologicalAge.windowDays) }.count
    }

    /// The last 60 days of biological age up to this page's day, for the sparkline.
    private var biologicalAgeHistory: [BiologicalAgeResult] {
        date.adding(days: -59).through(date).compactMap { health.biologicalAge(on: $0) }
    }

    // MARK: Header

    private var title: String {
        if isToday { return "Today" }
        if date == health.today.adding(days: -1) { return "Yesterday" }
        return date.noon.formatted(.dateTime.weekday(.wide))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Format.dayTitle(date)).sectionLabel()
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(.app(.largeTitle, .bold)).foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                if isToday && health.isSyncing { ProgressView() }
                Spacer()
                dayButton("chevron.left", label: "Previous day", enabled: canGoBack) { move(-1) }
                dayButton("chevron.right", label: "Next day", enabled: !isToday) { move(1) }
            }
            if isToday, let device = health.device {
                Label(deviceLine(device), systemImage: "applewatch.side.right")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            }
            if isToday && showsSwipeHint {
                Label("Swipe right to see earlier days", systemImage: "hand.draw")
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            }
            if !isToday {
                Button {
                    move(date.days(until: health.today))
                } label: {
                    Label("Back to today", systemImage: "arrow.uturn.forward")
                        .font(.app(.footnote, .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.effort)
            }
        }
    }

    private func dayButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.subheadline, .bold))
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func deviceLine(_ device: DeviceStatus) -> String {
        var parts = [device.name]
        if let lastSync = device.lastSync { parts.append("synced \(Format.ago(lastSync))") }
        if let battery = device.batteryPercent { parts.append("\(battery)%") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var banners: some View {
        if session.services.isDemo, let exitSampleData {
            Banner(symbol: "sparkles", message: "You're exploring sample data.", color: Theme.effort,
                   actionTitle: "Sign in") { exitSampleData() }
        }
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
    var change: Int?

    var body: some View {
        VStack(spacing: 16) {
            switch scores?.recovery ?? .calibrating(nightsCollected: nightsCollected) {
            case .scored(let recovery):
                ScoreDial(value: recovery.total, color: recovery.band.color, size: 210, label: "Recovery")
                VStack(spacing: 6) {
                    Text(recovery.band.title.uppercased())
                        .font(.app(.headline, .heavy)).tracking(2)
                        .foregroundStyle(recovery.band.color)
                    Text(recovery.band.advice)
                        .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    ChangeLabel(change: change)
                }
            case .calibrating(let nights):
                ScoreDial(value: nil, color: Theme.textSecondary, size: 210, label: "Calibrating",
                          placeholder: "\(min(nights, ScoreTuning.baselineMinimumNights))/\(ScoreTuning.baselineMinimumNights)")
                Text("Recovery unlocks after \(ScoreTuning.baselineMinimumNights) nights of HRV. Keep wearing your Fitbit Air to bed.")
                    .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            case .unavailable:
                ScoreDial(value: nil, color: Theme.textSecondary, size: 210, label: "Recovery")
                Text("No HRV from last night yet. It appears after your Fitbit Air syncs in the morning.")
                    .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            HStack {
                StatPill(title: "HRV", value: record?.hrvMs.map { "\(Int($0.rounded())) ms" } ?? "—")
                StatPill(title: "Resting HR", value: record?.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
                StatPill(title: "Sleep", value: record?.sleep.map { Format.duration(minutes: $0.minutesAsleep) } ?? "—")
            }
        }
        .frame(maxWidth: .infinity)
        .card()
        .overlay(alignment: .topTrailing) { CardChevron().padding(Theme.cardPadding) }
    }
}

// MARK: - Sleep and Effort

struct SleepCard: View {
    let scores: DayScores?
    let record: DayRecord?
    let goals: Goals
    var change: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Sleep").sectionLabel(); Spacer(); CardChevron() }
            ScoreDial(value: scores?.sleep?.total, color: Theme.sleep, size: 96, lineWidth: 10)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(record?.sleep.map { Format.duration(minutes: $0.minutesAsleep) } ?? "No sleep data")
                    .font(.app(.headline)).foregroundStyle(Theme.textPrimary)
                Text("Goal \(Format.duration(minutes: goals.sleepMinutes))")
                    .font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                ChangeLabel(change: change)
                    .padding(.top, 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

struct EffortCard: View {
    let scores: DayScores?
    let isToday: Bool
    var change: Int?
    /// Yesterday's final Effort (today's is still building, so it isn't compared directly).
    var yesterday: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Effort").sectionLabel(); Spacer(); CardChevron() }
            ScoreDial(value: scores?.effort, color: Theme.effort, size: 96, lineWidth: 10)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText).font(.app(.headline)).foregroundStyle(Theme.textPrimary)
                Text(scores.map { "Target \($0.effortTarget.lowerBound)–\($0.effortTarget.upperBound)" } ?? "Target —")
                    .font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                Group {
                    if isToday {
                        if let yesterday {
                            Text("Yesterday \(yesterday)").font(.app(.caption, .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        ChangeLabel(change: change, tint: Theme.effort)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var statusText: String {
        guard let scores, let effort = scores.effort else { return isToday ? "Not started" : "No data" }
        switch Effort.status(score: effort, target: scores.effortTarget) {
        case .below: return isToday ? "Building" : "Below target"
        case .onTarget: return "On target"
        case .above: return "Above target"
        }
    }
}

// MARK: - Sleep tip

struct SleepTipCard: View {
    let tip: SleepTip
    let isToday: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.symbol)
                .font(.app(.title3))
                .foregroundStyle(Theme.sleep)
                .frame(width: 40, height: 40)
                .background(Theme.sleep.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "Tonight's sleep tip" : "Sleep tip").sectionLabel()
                Text(tip.title).font(.app(.headline)).foregroundStyle(Theme.textPrimary)
                Text(tip.detail)
                    .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Effort target

struct EffortTargetCard: View {
    let scores: DayScores?
    let record: DayRecord?
    var isToday = true

    var body: some View {
        if let scores {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isToday ? "Today's Effort target" : "Effort target").sectionLabel()
                    Spacer()
                    Text("\(scores.effortTarget.lowerBound)–\(scores.effortTarget.upperBound)")
                        .font(.app(.headline)).monospacedDigit().foregroundStyle(Theme.effort)
                }
                EffortTrack(effort: scores.effort, target: scores.effortTarget)
                Text(coaching(scores))
                    .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
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
            return isToday
                ? "\(minutes) Active Zone Minutes so far. About \(max(0, needed - minutes)) more to reach your target."
                : "Finished with \(minutes) Active Zone Minutes, about \(max(0, needed - minutes)) short of the target."
        case .onTarget:
            return isToday ? "On target with \(minutes) Active Zone Minutes. Nice work."
                : "Finished on target with \(minutes) Active Zone Minutes."
        case .above:
            if scores.recovery.score?.band == .recover {
                return isToday ? "Above target on a Recover day. Ease off and let your body bounce back."
                    : "Went above target on a Recover day (\(minutes) Active Zone Minutes)."
            }
            return isToday ? "Above target with \(minutes) Active Zone Minutes. Bonus work, but recover well tonight."
                : "Finished above target with \(minutes) Active Zone Minutes."
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
            Label {
                Text("Flames count days in a row. Shields are banked rest days: earn one every \(ScoreTuning.restTokenEveryDays) days in a row (hold up to \(ScoreTuning.maxRestTokens)). A missed day uses a shield instead of ending the streak.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "shield.fill").foregroundStyle(Theme.effort)
            }
            .font(.app(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 2)
        }
    }

    private func chip(_ kind: StreakKind, _ state: StreakState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(state.current > 0 ? Theme.recoverySteady : Theme.textSecondary)
                Text("\(state.current)").font(.scoreNumber(24)).foregroundStyle(Theme.textPrimary)
            }
            Text(shortTitle(kind)).font(.app(.caption, .semibold)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 2) {
                ForEach(0..<ScoreTuning.maxRestTokens, id: \.self) { index in
                    Image(systemName: index < state.restTokens ? "shield.fill" : "shield")
                        .font(.app(.caption2))
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
                            Text(challenge.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text("\(Format.count(challenge.progress))/\(Format.count(challenge.target))")
                                .font(.app(.caption)).monospacedDigit().foregroundStyle(Theme.textSecondary)
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
                            Text("Group challenge").font(.app(.caption)).foregroundStyle(Theme.textSecondary)
                            Text(group.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.app(.footnote)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }
}
