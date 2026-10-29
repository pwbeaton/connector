import SwiftUI

/// What a tap on Today opens.
nonisolated enum TodayDetail: Identifiable, Hashable, Sendable {
    case score(ScoreKind, CivilDate)
    case biologicalAge(CivilDate)

    var id: String {
        switch self {
        case .score(let kind, let date): "\(kind.rawValue)-\(date)"
        case .biologicalAge(let date): "age-\(date)"
        }
    }
}

/// Today: Recovery front and center, Sleep and Effort, the Effort target, tonight's
/// bedtime, streaks, and biological age. Swipe right to page back through earlier days.
struct TodayView: View {
    @Environment(AppSession.self) private var session
    @State private var selectedDate: CivilDate?
    @State private var detail: TodayDetail?

    private var health: HealthModel { session.health }

    var body: some View {
        let dates = health.browsableDates
        let current = selectedDate.flatMap { dates.contains($0) ? $0 : nil } ?? health.today
        TabView(selection: Binding(get: { current }, set: { selectedDate = $0 })) {
            ForEach(dates, id: \.self) { date in
                DayPage(date: date,
                        canGoBack: date > (dates.first ?? date),
                        move: { days in move(by: days, from: date, within: dates) },
                        showDetail: { detail = $0 })
                    .tag(date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectedDate)
        .sensoryFeedback(.success, trigger: health.promotion) { _, new in new != nil }
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

/// "TUE · OCT 27"
nonisolated enum DayFormat {
    static func eyebrow(_ date: CivilDate) -> String {
        let weekday = date.noon.formatted(.dateTime.weekday(.abbreviated))
        let monthDay = date.noon.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) · \(monthDay)"
    }
}

/// Tracks how far a ScrollView has scrolled, for the compact header.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A screen that scrolls under a compact title once its large title is gone.
struct PlutoScreen<Content: View>: View {
    let title: String
    let subtitle: String
    var startsAtBottom = false
    var refresh: (() async -> Void)?
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 130)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("screen")).minY)
                })
        }
        .coordinateSpace(name: "screen")
        .onPreferenceChange(ScrollOffsetKey.self) { offset = $0 }
        .defaultScrollAnchor(startsAtBottom ? .bottom : .top)
        .refreshable { await refresh?() }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            compactHeader.opacity(offset < -64 ? 1 : 0).animation(.easeOut(duration: 0.15), value: offset < -64)
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 2) {
            Text(title).font(.archivo(17, .bold)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.mono(10, .medium)).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(Theme.background.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One day of stats. Today also shows banners and streaks.
struct DayPage: View {
    @Environment(AppSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.exitSampleData) private var exitSampleData

    let date: CivilDate
    let canGoBack: Bool
    let move: (Int) -> Void
    let showDetail: (TodayDetail) -> Void

    private var health: HealthModel { session.health }
    private var isToday: Bool { date == health.today }
    private var scores: DayScores? { health.scores(on: date) }
    private var record: DayRecord? { health.record(on: date) }

    var body: some View {
        PlutoScreen(title: title, subtitle: DayFormat.eyebrow(date), startsAtBottom: isToday && session.options.startsAtBottom,
                    refresh: { await session.refresh() }) {
            header
            if isToday, let device = health.device { deviceLine(device).padding(.top, -4) }
            if isToday { banners }
            if !isToday { backToToday }
            Button { showDetail(.score(.recovery, date)) } label: {
                RecoveryCard(scores: scores, record: record, nightsCollected: nightsCollected,
                             change: health.dayChange(.recovery, on: date),
                             yesterday: health.scores(on: date.adding(days: -1))?.recovery.score?.total)
            }
            .buttonStyle(.pressableCard)
            .accessibilityHint("Shows your Recovery history")
            HStack(alignment: .top, spacing: 14) {
                Button { showDetail(.score(.sleep, date)) } label: {
                    ScoreMiniCard(kind: .sleep, value: scores?.sleep?.total, target: nil,
                                  footer: AnyView(ChangeLabel(change: health.dayChange(.sleep, on: date))))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Shows your Sleep history")
                Button { showDetail(.score(.effort, date)) } label: {
                    ScoreMiniCard(kind: .effort, value: scores?.effort, target: scores?.effortTarget,
                                  footer: AnyView(Text(scores.map { "Target \($0.effortTarget.lowerBound)–\($0.effortTarget.upperBound)" } ?? "Target —")
                                    .font(.archivo(13)).foregroundStyle(Theme.textSecondary)))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Shows your Effort history")
            }
            .fixedSize(horizontal: false, vertical: true)
            EffortTargetCard(scores: scores, record: record, isToday: isToday)
            if isToday, let plan = health.bedtimePlan(on: date) {
                Button { showDetail(.score(.sleep, date)) } label: {
                    TonightCard(plan: plan, debt: health.sleepDebt(on: date))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Shows your sleep debt and sleep history")
            }
            if isToday {
                StreaksRow(streaks: health.snapshot.streaks)
            }
            Button { showDetail(.biologicalAge(date)) } label: {
                BiologicalAgeCard(result: health.biologicalAge(on: date), trend: health.biologicalAgeTrend(on: date),
                                  hasAge: health.chronologicalAge != nil, daysOfData: daysOfData)
            }
            .buttonStyle(.pressableCard)
            .padding(.top, isToday ? 14 : 0)
            .accessibilityHint("Shows what moves your biological age")
            Text("Scores are estimates to guide training, not medical advice.")
                .font(.archivo(12)).foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private var nightsCollected: Int {
        isToday ? health.snapshot.hrvNightsCollected
            : Baselines.nightsCollected(before: date.adding(days: 1), in: health.records) { $0.hrvMs }
    }

    private var daysOfData: Int {
        health.records.filter { $0.date <= date && $0.date > date.adding(days: -BiologicalAge.windowDays) }.count
    }

    // MARK: Header

    private var title: String {
        if isToday { return "Today" }
        if date == health.today.adding(days: -1) { return "Yesterday" }
        return date.noon.formatted(.dateTime.weekday(.wide))
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(DayFormat.eyebrow(date)).eyebrow()
                HStack(spacing: 10) {
                    Text(title).screenTitle().lineLimit(1).minimumScaleFactor(0.7)
                    if isToday && health.isSyncing { ProgressView() }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                RoundIconButton(symbol: "chevron.left", label: "Previous day", enabled: canGoBack) { move(-1) }
                RoundIconButton(symbol: "chevron.right", label: "Next day", enabled: !isToday) { move(1) }
            }
        }
    }

    private var backToToday: some View {
        Button { move(date.days(until: health.today)) } label: {
            Label("Back to today", systemImage: "arrow.uturn.forward")
                .font(.archivo(14, .semibold))
                .padding(.horizontal, 14).frame(height: 36)
                .overlay(Capsule().strokeBorder(Theme.controlStroke))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.teal)
        .padding(.top, -4)
    }

    private func deviceLine(_ device: DeviceStatus) -> some View {
        HStack(spacing: 8) {
            TrackerGlyph().foregroundStyle(Theme.textSecondary)
            Text(device.name).font(.archivo(13, .semibold)).foregroundStyle(Theme.textPrimary)
            if let lastSync = device.lastSync {
                Dot()
                Text("Synced \(Format.ago(lastSync))").font(.archivo(13)).foregroundStyle(Theme.textSecondary)
            }
            if let battery = device.batteryPercent {
                Dot()
                HStack(spacing: 5) {
                    BatteryGlyph(level: Double(battery) / 100)
                    Text("\(battery)%").font(.archivo(13))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var banners: some View {
        if session.services.isDemo, let exitSampleData {
            Banner(symbol: "sparkle", message: "You're exploring sample data", actionTitle: "Sign in") { exitSampleData() }
        }
        if let tier = health.promotion {
            Banner(symbol: "shield.fill", message: "Promoted to \(tier.title)! Four weeks of consistency earned it.",
                   color: tier.color, actionTitle: "Nice") {
                health.promotion = nil
            }
        }
        if health.needsReconnect {
            Banner(symbol: "link", message: "Your Fitbit connection expired.", color: Theme.effort,
                   actionTitle: "Reconnect") {
                Task {
                    await session.reconnectGoogle { url, scheme in
                        try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: scheme)
                    }
                }
            }
        } else if let problem = health.syncProblem {
            Banner(symbol: "wifi.exclamationmark", message: problem, color: Theme.effort)
        }
        if !health.state.missingCategories.isEmpty {
            Banner(symbol: "lock", message: "Missing access to \(health.state.missingCategories.sorted().map(\.title).joined(separator: ", ")). Sign out and back in to grant it.",
                   color: Theme.effort)
        }
        if !health.hasData && !health.isSyncing {
            Banner(symbol: "moon.zzz", message: "No data yet. Wear your Fitbit Air tonight and sync it in the Google Health app.",
                   color: Theme.sleep)
        }
    }
}

// MARK: - Small pieces

/// A 44 pt round outline button (previous / next day, invite).
struct RoundIconButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(enabled ? Theme.surface : .clear, in: Circle())
                .overlay(Circle().strokeBorder(enabled ? Theme.controlStroke : Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textPrimary : Theme.textFaint)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct Dot: View {
    var body: some View {
        Circle().fill(Theme.textFaint).frame(width: 3, height: 3).accessibilityHidden(true)
    }
}

/// The Fitbit Air silhouette: a rounded pill with two bands.
struct TrackerGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            let body = Path(roundedRect: CGRect(x: 8 * s, y: 2.5 * s, width: 8 * s, height: 19 * s), cornerRadius: 4 * s)
            var bands = Path()
            bands.move(to: CGPoint(x: 8 * s, y: 9.5 * s)); bands.addLine(to: CGPoint(x: 16 * s, y: 9.5 * s))
            bands.move(to: CGPoint(x: 8 * s, y: 14.5 * s)); bands.addLine(to: CGPoint(x: 16 * s, y: 14.5 * s))
            context.stroke(body, with: .foreground, lineWidth: 1.8 * s)
            context.stroke(bands, with: .foreground, lineWidth: 1.8 * s)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

struct BatteryGlyph: View {
    let level: Double

    var body: some View {
        Canvas { context, _ in
            context.stroke(Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: 18, height: 10.5), cornerRadius: 3),
                           with: .foreground, lineWidth: 1.5)
            context.fill(Path(roundedRect: CGRect(x: 2.5, y: 2.5, width: 14.5 * min(1, max(0.05, level)), height: 7), cornerRadius: 1.5),
                         with: .foreground)
            context.fill(Path(roundedRect: CGRect(x: 20, y: 4, width: 1.5, height: 4), cornerRadius: 0.75), with: .foreground)
        }
        .frame(width: 22, height: 12)
        .accessibilityHidden(true)
    }
}

/// A tinted pill: "Steady", "Low".
struct StatusPill: View {
    let text: String
    let background: Color
    let foreground: Color
    var size: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.archivo(size, .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, size == 14 ? 14 : 11)
            .padding(.vertical, size == 14 ? 7 : 5)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

// MARK: - Recovery

struct RecoveryCard: View {
    let scores: DayScores?
    let record: DayRecord?
    let nightsCollected: Int
    var change: Int?
    var yesterday: Int?

    private var recovery: Recovery { scores?.recovery ?? .calibrating(nightsCollected: nightsCollected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recovery").sectionLabel()
                Spacer()
                HStack(spacing: 2) {
                    Text("30-day trend").font(.archivo(13, .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.teal)
            }
            .frame(height: 24)
            HStack(alignment: .bottom) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(bigNumber)
                        .font(.scoreNumber(recovery.score == nil ? 72 : 128))
                        .tracking(recovery.score == nil ? 0 : -3.8)
                        .foregroundStyle(recovery.score == nil ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(1)
                        .lineBox(0.8, size: recovery.score == nil ? 72 : 128)
                    Text(recovery.score == nil ? "" : "/ 100").font(.archivo(15, .medium)).foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    if let score = recovery.score {
                        StatusPill(text: score.band.title, background: score.band.tint, foreground: score.band.textColor)
                        ChangeLabel(change: change)
                    } else if case .calibrating = recovery {
                        StatusPill(text: "Calibrating", background: Theme.surfaceRaised, foreground: Theme.textSecondary)
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(.top, 10)
            if let score = recovery.score {
                TickScale(range: 0...100,
                          minor: .init(divisions: 50, top: 12, height: 16),
                          major: .init(divisions: 10, top: 4, height: 32),
                          fill: Double(score.total), fillColor: Theme.teal,
                          markers: markers(score.total),
                          height: 40, labelRoom: 18,
                          axis: [(0, "0"), (25, "25"), (50, "50"), (75, "75"), (100, "100")], axisGap: 8)
                    .padding(.top, 12)
            }
            Text(message)
                .font(.archivo(17, .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(1.35, size: 17)
                .padding(.top, 18)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, 18).padding(.bottom, 16)
            HStack(alignment: .top, spacing: 12) {
                metric("HRV", record?.hrvMs.map { [("\(Int($0.rounded()))", "ms")] })
                metric("Resting HR", record?.restingHeartRate.map { [("\(Int($0.rounded()))", "bpm")] })
                metric("Sleep", record?.sleep.map { UnitNumber.duration(minutes: $0.minutesAsleep) })
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var bigNumber: String {
        switch recovery {
        case .scored(let score): "\(score.total)"
        case .calibrating(let nights): "\(min(nights, ScoreTuning.baselineMinimumNights))/\(ScoreTuning.baselineMinimumNights)"
        case .unavailable: "—"
        }
    }

    private var message: String {
        switch recovery {
        case .scored(let score): score.band.advice
        case .calibrating: "Recovery unlocks after \(ScoreTuning.baselineMinimumNights) nights of HRV. Keep wearing your Fitbit Air to bed."
        case .unavailable: "No HRV from last night yet. It appears after your Fitbit Air syncs in the morning."
        }
    }

    private var accessibilitySummary: String {
        if let score = recovery.score { return "Recovery \(score.total) out of 100, \(score.band.title). \(score.band.advice)" }
        return "Recovery. \(message)"
    }

    private func markers(_ value: Int) -> [TickScale.Marker] {
        var result: [TickScale.Marker] = []
        if let yesterday {
            result.append(.init(value: Double(yesterday), color: Theme.markerDashed, dashed: true, top: -2, height: 44,
                                label: "yday \(yesterday)", labelPlacement: .trailing, labelTop: -16))
        }
        result.append(.init(value: Double(value), color: Theme.textPrimary, top: -4, height: 48))
        return result
    }

    private func metric(_ title: String, _ parts: [(value: String, unit: String?)]?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundStyle(Theme.textMuted).lineLimit(1)
            if let parts {
                UnitNumber(parts: parts)
            } else {
                Text("—").font(.archivo(28, .semibold, width: 75)).foregroundStyle(Theme.textFaint).lineBox(1, size: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sleep and Effort

/// The half-width Sleep or Effort card: label, big number, mini ruler, footer.
struct ScoreMiniCard: View {
    let kind: ScoreKind
    let value: Int?
    let target: ClosedRange<Int>?
    let footer: AnyView

    private var color: Color { kind == .sleep ? Theme.sleep : Theme.effort }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind.title).sectionLabel()
                Spacer()
                CardChevron()
            }
            Text(value.map(String.init) ?? "—")
                .font(.scoreNumber(64))
                .tracking(-1.28)
                .foregroundStyle(value == nil ? Theme.textFaint : Theme.textPrimary)
                .lineBox(0.82, size: 64)
            TickScale(range: 0...100,
                      minor: .init(divisions: 33, top: 0, height: 14),
                      fill: value.map(Double.init), fillColor: color,
                      bands: target.map { [.init(from: Double($0.lowerBound), to: Double($0.upperBound), color: Theme.effortTint,
                                                 top: -3, height: 20, radius: 4)] } ?? [],
                      height: 14, labelRoom: 3)
                .frame(width: 132)
            footer
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), radius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title) \(value.map { "\($0) out of 100" } ?? "no data")")
    }
}

// MARK: - Effort target

struct EffortTargetCard: View {
    let scores: DayScores?
    let record: DayRecord?
    var isToday = true

    var body: some View {
        if let scores {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isToday ? "Today's effort target" : "Effort target").sectionLabel()
                    Spacer()
                    Text("\(scores.effortTarget.lowerBound)–\(scores.effortTarget.upperBound)")
                        .font(.archivo(32, .semibold, width: 70))
                        .foregroundStyle(Theme.effort)
                        .lineBox(1, size: 32)
                }
                TickScale(range: 0...100,
                          minor: .init(divisions: 50, top: 10, height: 16),
                          major: .init(divisions: 10, top: 2, height: 32),
                          fill: Double(scores.effort ?? 0), fillColor: Theme.effort, fillsMajor: false,
                          bands: [.init(from: Double(scores.effortTarget.lowerBound), to: Double(scores.effortTarget.upperBound),
                                        color: Theme.effortTint, top: -2, height: 40, radius: 6,
                                        label: "target", labelColor: Theme.effortText)],
                          markers: [.init(value: Double(scores.effort ?? 0), color: Theme.textPrimary, top: -4, height: 44,
                                          label: "now \(scores.effort ?? 0)", labelColor: Theme.textPrimary,
                                          labelPlacement: .trailing)],
                          height: 36, labelRoom: 20,
                          axis: [(0, "0"), (25, "25"), (50, "50"), (75, "75"), (100, "100")])
                    .padding(.top, 10)
                coaching(scores)
                    .font(.archivo(15))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(1.45, size: 15)
                    .padding(.top, 16)
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private func strong(_ string: String) -> Text {
        Text(string).font(.archivo(15, .bold)).foregroundStyle(Theme.textPrimary)
    }

    private func coaching(_ scores: DayScores) -> Text {
        let minutes = record?.activeZoneMinutes ?? 0
        let needed = max(0, Effort.activeZoneMinutes(forScore: scores.effortTarget.lowerBound) - minutes)
        let azm = strong("\(minutes) Active Zone \(minutes == 1 ? "Minute" : "Minutes")")
        switch Effort.status(score: scores.effort ?? 0, target: scores.effortTarget) {
        case .below:
            return isToday
                ? azm + Text(" so far. About ") + strong("\(needed) more") + Text(" to reach your target.")
                : Text("Finished with ") + azm + Text(", about ") + strong("\(needed) short") + Text(" of the target.")
        case .onTarget:
            return Text(isToday ? "On target with " : "Finished on target with ") + azm + Text(". Nice work.")
        case .above:
            if scores.recovery.score?.band == .recover {
                return Text("Above target on a Recover day with ") + azm + Text(". Ease off and let your body bounce back.")
            }
            return Text("Above target with ") + azm + Text(". Bonus work, but recover well tonight.")
        }
    }
}

// MARK: - Tonight

/// Tonight's bedtime on a 3-hour ruler next to your usual bedtime, plus sleep debt.
struct TonightCard: View {
    let plan: BedtimePlan
    let debt: SleepDebt?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "moon")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.sleep)
                    .frame(width: 52, height: 52)
                    .background(Theme.sleepTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tonight · Bed by").sectionLabel()
                    clock
                }
            }
            if let shift = BedtimeFormat.shift(plan.shiftFromUsual) {
                HStack(spacing: 6) {
                    if let minutes = plan.shiftFromUsual, abs(minutes) >= 10 {
                        Image(systemName: minutes < 0 ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                            .font(.system(size: 9))
                    }
                    Text(shift)
                }
                .font(.archivo(14, .semibold))
                .foregroundStyle(Theme.sleep)
                .padding(.top, 14)
            }
            timeline.padding(.top, 10)
            if let debt {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, 18).padding(.bottom, 14)
                HStack {
                    Text("Sleep debt").sectionLabel()
                    Spacer()
                    HStack(spacing: 10) {
                        if debt.minutes == 0 {
                            Text("None").font(.archivo(28, .semibold, width: 75)).foregroundStyle(Theme.textPrimary)
                                .lineBox(1, size: 28)
                        } else {
                            UnitNumber(parts: UnitNumber.duration(minutes: debt.minutes))
                        }
                        StatusPill(text: debt.level.title, background: debt.level.tint, foreground: debt.level.textColor, size: 13)
                    }
                }
            }
        }
        .card(padding: EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
        .accessibilityElement(children: .combine)
    }

    private var clock: some View {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(hour: plan.bedtime / 60, minute: plan.bedtime % 60)) ?? .now
        let time = date.formatted(.dateTime.hour().minute()).components(separatedBy: " ")
        return (Text(time.first ?? "").font(.archivo(44, .semibold, width: 70)).tracking(-0.44)
            + Text(time.count > 1 ? " " + time[1] : "").font(.archivo(18, .semibold, width: 90)))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize()
            .lineBox(0.85, size: 44)
    }

    private static func unwrap(_ minute: Int) -> Int { minute < 12 * 60 ? minute + 1440 : minute }

    /// The 3-hour window holding both tonight's and your usual bedtime.
    private var window: (start: Int, end: Int) {
        let usual = plan.usualBedtime ?? plan.bedtime
        let earliest = min(Self.unwrap(plan.bedtime), Self.unwrap(usual))
        let latest = max(Self.unwrap(plan.bedtime), Self.unwrap(usual))
        var start = (earliest / 60 - 1) * 60
        if latest > start + 180 - 20 { start = (latest / 60 - 2) * 60 }
        return (start, start + 180)
    }

    private var timeline: some View {
        let window = window
        let bed = Double(Self.unwrap(plan.bedtime))
        var markers: [TickScale.Marker] = []
        var bands: [TickScale.Band] = []
        if let usualMinute = plan.usualBedtime {
            let usual = Double(Self.unwrap(usualMinute))
            if abs(usual - bed) >= 5 {
                bands.append(.init(from: min(bed, usual), to: max(bed, usual), color: Theme.sleepTint, top: -2, height: 34))
                markers.append(.init(value: usual, color: Theme.markerDashed, dashed: true, top: -4, height: 38,
                                     label: "usual \(shortClock(usualMinute))", labelPlacement: .trailing, labelTop: -22))
            }
        }
        markers.append(.init(value: bed, color: Theme.sleep, top: -6, height: 42,
                             label: shortClock(plan.bedtime), labelColor: Theme.sleep, labelWeight: .medium))
        let hours = stride(from: window.start, through: window.end, by: 60).map { minute -> (value: Double, label: String) in
            let hour24 = (minute / 60) % 24
            let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
            let edge = minute == window.start || minute == window.end
            return (Double(minute), edge ? "\(hour) \(hour24 < 12 ? "AM" : "PM")" : "\(hour)")
        }
        return TickScale(range: Double(window.start)...Double(window.end),
                         minor: .init(divisions: 12, top: 9, height: 12),
                         major: .init(divisions: 3, top: 2, height: 26),
                         bands: bands,
                         line: .init(top: 14, height: 2, color: Theme.trackLine),
                         markers: markers,
                         height: 30, labelRoom: 22,
                         axis: hours)
    }

    private func shortClock(_ minute: Int) -> String {
        let m = minute % 1440
        let hour = (m / 60) % 12 == 0 ? 12 : (m / 60) % 12
        return String(format: "%d:%02d", hour, m % 60)
    }
}

extension SleepDebt.Level {
    var tint: Color {
        switch self {
        case .low: Theme.tealTint
        case .moderate: Theme.goldTint
        case .high: Theme.effortTint
        }
    }

    var textColor: Color {
        switch self {
        case .low: Theme.tealDeep
        case .moderate: Theme.goldText
        case .high: Theme.effortText
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
                .font(.system(size: 20))
                .foregroundStyle(Theme.sleep)
                .frame(width: 44, height: 44)
                .background(Theme.sleepTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "Tonight's sleep tip" : "Sleep tip").sectionLabel()
                Text(tip.title).font(.archivo(17, .bold)).foregroundStyle(Theme.textPrimary)
                Text(tip.detail)
                    .font(.archivo(15)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Streaks

struct StreaksRow: View {
    let streaks: [StreakKind: StreakState]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaks").sectionHeading().padding(.top, 14).accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                ForEach(StreakKind.allCases, id: \.self) { kind in
                    chip(kind, streaks[kind] ?? StreakState())
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ShieldGlyph(earned: true, size: 14).padding(.top, 1)
                Text("Flames count days in a row. Shields are banked rest days: earn one every \(ScoreTuning.restTokenEveryDays) days in a row (hold up to \(ScoreTuning.maxRestTokens)). A missed day uses a shield.")
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(1.45, size: 13)
            }
            .font(.archivo(13))
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 2)
        }
    }

    private func chip(_ kind: StreakKind, _ state: StreakState) -> some View {
        let active = state.current > 0
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if active { Image(systemName: "flame.fill").foregroundStyle(Theme.effortTint) }
                Image(systemName: "flame").foregroundStyle(active ? Theme.effort : Theme.textFaint)
            }
            .font(.system(size: 19))
            Text("\(state.current)")
                .font(.scoreNumber(48))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textMuted)
                .lineBox(0.85, size: 48)
            Text(shortTitle(kind)).font(.archivo(13, .semibold)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 3) {
                ForEach(0..<ScoreTuning.maxRestTokens, id: \.self) { index in
                    ShieldGlyph(earned: index < state.restTokens, size: 12)
                }
                Text("\(state.restTokens)/\(ScoreTuning.maxRestTokens)").font(.mono(10)).foregroundStyle(Theme.textMuted)
                    .padding(.leading, 4)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: EdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14), radius: 22)
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

struct ShieldGlyph: View {
    let earned: Bool
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            if earned { Image(systemName: "shield.fill").foregroundStyle(Theme.tealTint) }
            Image(systemName: "shield").foregroundStyle(earned ? Theme.teal : Theme.textFaint)
        }
        .font(.system(size: size))
        .accessibilityHidden(true)
    }
}

// MARK: - Biological age

struct BiologicalAgeCard: View {
    let result: BiologicalAgeResult?
    let trend: BiologicalAgeTrend?
    let hasAge: Bool
    let daysOfData: Int

    private var older: Bool { (result?.difference ?? 0) > 0.05 }
    private var color: Color { older ? Theme.effort : Theme.teal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Biological age").sectionLabel()
                Spacer()
                CardChevron()
            }
            .frame(height: 24)
            if let result {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(AgeFormat.age(result.biologicalAge))
                        .font(.scoreNumber(84))
                        .tracking(-1.68)
                        .foregroundStyle(color)
                        .lineBox(0.8, size: 84)
                    Text("vs \(result.chronologicalAge) actual").font(.archivo(15, .medium)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 10)
                Text(AgeFormat.difference(result.difference))
                    .font(.archivo(17, .medium)).foregroundStyle(Theme.textPrimary)
                    .padding(.top, 12)
                scale(result).padding(.top, 12)
                if let trend {
                    trendCapsule(trend, on: result.date).padding(.top, 18)
                } else {
                    Text("Your trend appears after another week of data.")
                        .font(.archivo(13)).foregroundStyle(Theme.textMuted).padding(.top, 18)
                }
            } else {
                Text(hasAge
                     ? "Biological age needs \(BiologicalAge.minimumDays) days of data. You have \(min(daysOfData, BiologicalAge.minimumDays)) so far."
                     : "Add your age to see your biological age: how old your body acts based on fitness, activity, and sleep.")
                    .font(.archivo(15)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func trendCapsule(_ trend: BiologicalAgeTrend, on date: CivilDate) -> some View {
        let (symbol, foreground, background): (String, Color, Color) = switch trend.direction {
        case .steady: ("arrow.right", Theme.textSecondary, Theme.surfaceRaised)
        case .improving: ("arrow.down.right", Theme.tealDeep, Theme.tealTint)
        case .worsening: ("arrow.up.right", Theme.effortText, Theme.effortTint)
        }
        return HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
            Text(AgeFormat.trend(trend, on: date))
        }
        .font(.archivo(14, .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scale(_ result: BiologicalAgeResult) -> some View {
        let bio = result.biologicalAge, actual = Double(result.chronologicalAge)
        var low = (min(bio, actual) / 5).rounded(.down) * 5
        if min(bio, actual) - low < 2 { low -= 5 }
        let high = max(low + 15, (max(bio, actual) / 5).rounded(.up) * 5)
        return TickScale(range: low...high,
                         minor: .init(divisions: Int((high - low) * 2), top: 9, height: 12),
                         major: .init(divisions: Int((high - low) / 5), top: 2, height: 26),
                         bands: [.init(from: min(bio, actual), to: max(bio, actual), color: older ? Theme.effortTint : Theme.tealTint,
                                       top: -2, height: 34)],
                         markers: [
                            .init(value: bio, color: color, top: -6, height: 42, label: AgeFormat.age(bio),
                                  labelColor: color, labelWeight: .medium),
                            .init(value: actual, color: Theme.textPrimary, top: -6, height: 42, label: "\(result.chronologicalAge)",
                                  labelColor: Theme.textPrimary, labelWeight: .medium),
                         ],
                         height: 30, labelRoom: 22,
                         axis: stride(from: low, through: high, by: 5).map { (value: $0, label: "\(Int($0))") })
    }
}

// MARK: - Personal challenges (opened from the group challenge card)

struct ChallengesSection: View {
    let challenges: [Challenge]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(challenges) { challenge in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: challenge.isComplete ? "checkmark.seal.fill" : "target")
                            .foregroundStyle(challenge.isComplete ? Theme.teal : Theme.effort)
                        Text(challenge.title).font(.archivo(15, .semibold)).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("\(Format.count(challenge.progress))/\(Format.count(challenge.target))")
                            .font(.mono(11)).foregroundStyle(Theme.textMuted)
                    }
                    ProgressBar(fraction: challenge.fraction, color: challenge.isComplete ? Theme.teal : Theme.effort, height: 4)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
