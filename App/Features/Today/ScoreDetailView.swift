import Charts
import SwiftUI

extension ScoreKind {
    var color: Color {
        switch self {
        case .recovery: Theme.recoveryGo
        case .sleep: Theme.sleep
        case .effort: Theme.effort
        }
    }

    /// One paragraph on what the score means.
    var explanation: String {
        switch self {
        case .recovery:
            "How ready your body is today. Half comes from last night's HRV against your 30-day normal, a fifth from resting heart rate against your normal, and the rest from your Sleep score. 67+ is Go, 34–66 Steady, 33 or less Recover."
        case .sleep:
            "Half the points are hours asleep against your goal, and each missing hour costs more than the last (90% of your goal earns 81% of those points). A quarter are deep + REM sleep: full marks at 42% of the night, none at 20%. 15 are efficiency, from 80% to 95% of time in bed asleep (85%+ is what sleep experts call good). 10 are waking within an hour of your usual time."
        case .effort:
            "Built from Active Zone Minutes: it climbs fast at first and flattens near the top, so 100 is rare. About 22 minutes scores 39, 45 scores 63, and 90 scores 86. Your daily target follows your Recovery."
        }
    }
}

/// The history behind one score: a chart of every day, the trend, and what feeds it.
struct ScoreDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let kind: ScoreKind
    let date: CivilDate
    @State private var range = 30

    private var health: HealthModel { session.health }

    private struct Point: Identifiable {
        let date: CivilDate
        let value: Int
        let color: Color
        var id: CivilDate { date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    Picker("Range", selection: $range) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    chartCard
                    breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it's calculated").sectionLabel()
                        Text(kind.explanation)
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Summary

    private var value: Int? { kind.value(in: health.scores(on: date)) }

    private var valueColor: Color {
        if kind == .recovery, let band = health.scores(on: date)?.recovery.score?.band { return band.color }
        return kind.color
    }

    private var summary: some View {
        VStack(spacing: 10) {
            Text(Format.dayTitle(date)).sectionLabel()
            Text(value.map(String.init) ?? "—")
                .font(.scoreNumber(72))
                .foregroundStyle(valueColor)
            if kind == .effort && date == health.today {
                Text("Still building today").font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ChangeLabel(change: health.dayChange(kind, on: date), tint: kind == .effort ? Theme.effort : nil)
            }
            if let week = health.weekComparison(kind, endingOn: date) {
                trendLine(week)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func trendLine(_ week: ScoreTrend.WeekComparison) -> some View {
        let average = Int(week.recentAverage.rounded())
        let change = Int(abs(week.change).rounded())
        let (symbol, text, color): (String, String, Color) = switch week.direction {
        case .up: ("arrow.up.right", "Trending up: 7-day average \(average), up \(change) on the week before", kind == .effort ? Theme.effort : Theme.recoveryGo)
        case .down: ("arrow.down.right", "Trending down: 7-day average \(average), down \(change) on the week before", kind == .effort ? Theme.effort : Theme.recoveryRest)
        case .flat: ("arrow.right", "Holding steady: 7-day average \(average), about the same as the week before", Theme.textSecondary)
        }
        return Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Chart

    private var points: [Point] {
        let start = health.today.adding(days: -(range - 1))
        return health.snapshot.days.filter { $0.date >= start }.compactMap { day in
            kind.value(in: day).map { value in
                let color = kind == .recovery ? (day.recovery.score?.band.color ?? kind.color) : kind.color
                return Point(date: day.date, value: value, color: color)
            }
        }
    }

    private struct AveragePoint: Identifiable {
        let date: CivilDate
        let value: Double
        var id: CivilDate { date }
    }

    private var averageLine: [AveragePoint] {
        let start = health.today.adding(days: -(range - 1))
        return start.through(health.today).compactMap { day in
            ScoreTrend.rollingAverage(kind, on: day, scores: health.snapshot.days).map { AveragePoint(date: day, value: $0) }
        }
    }

    private var chartCard: some View {
        let points = points
        let values = points.map(\.value)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last \(range) days").sectionLabel()
                Spacer()
                Label("7-day average", systemImage: "line.diagonal")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if points.isEmpty {
                Text("No data in this period.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Day", point.date.noon, unit: .day), y: .value(kind.title, point.value))
                            .foregroundStyle(point.color.opacity(point.date == date ? 1 : 0.55))
                            .cornerRadius(range > 30 ? 1 : 3)
                    }
                    ForEach(averageLine) { point in
                        LineMark(x: .value("Day", point.date.noon, unit: .day), y: .value("Average", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.textPrimary)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    if points.contains(where: { $0.date == date }) {
                        RuleMark(x: .value("Selected", date.noon, unit: .day))
                            .foregroundStyle(Theme.textSecondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : (range == 30 ? 7 : 21))) { _ in
                        AxisValueLabel(format: range == 7 ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 190)
                HStack {
                    StatPill(title: "Average", value: "\(values.reduce(0, +) / max(1, values.count))")
                    StatPill(title: "Best", value: values.max().map(String.init) ?? "—")
                    StatPill(title: "Lowest", value: values.min().map(String.init) ?? "—")
                }
            }
        }
        .card()
    }

    // MARK: Breakdown

    @ViewBuilder private var breakdown: some View {
        let scores = health.scores(on: date)
        let record = health.record(on: date)
        switch kind {
        case .recovery:
            if let recovery = scores?.recovery.score {
                partsCard(title: "What made today's score", parts: [
                    ("HRV vs your normal", recovery.hrvComponent, 100, record?.hrvMs.map { "\(Int($0.rounded())) ms" }),
                    ("Resting HR vs your normal", recovery.restingHRComponent, 100, record?.restingHeartRate.map { "\(Int($0.rounded())) bpm" }),
                    ("Sleep score", recovery.sleepComponent, 100, nil),
                ])
            }
            rawTrend(title: "HRV", unit: "ms", color: Theme.recoveryGo) { $0.hrvMs }
            rawTrend(title: "Resting heart rate", unit: "bpm", color: Theme.recoveryRest) { $0.restingHeartRate }
        case .sleep:
            if let sleep = scores?.sleep {
                partsCard(title: "Where the points came from", parts: [
                    ("Duration", sleep.duration, ScoreTuning.sleepDurationPoints, record?.sleep.map { Format.duration(minutes: $0.minutesAsleep) }),
                    ("Deep + REM", sleep.restoration, ScoreTuning.sleepRestorationPoints, record?.sleep.flatMap(restorativeText)),
                    ("Efficiency", sleep.efficiency, ScoreTuning.sleepEfficiencyPoints, record?.sleep.map(efficiencyText)),
                    ("Consistency", sleep.consistency, ScoreTuning.sleepConsistencyPoints, record?.sleep.map { "woke \(Format.clock(minuteOfDay: $0.wakeMinuteOfDay))" }),
                ])
            }
            if let tip = health.sleepTip(on: date) {
                SleepTipCard(tip: tip, isToday: date == health.today)
            }
            if let debt = health.sleepDebt(on: date) {
                SleepDebtCard(debt: debt, plan: date == health.today ? health.bedtimePlan(on: date) : nil)
            }
            rawTrend(title: "Hours asleep", unit: "h", color: Theme.sleep, goal: Double(health.goals.sleepMinutes) / 60) {
                $0.sleep.map { Double($0.minutesAsleep) / 60 }
            }
        case .effort:
            if let scores {
                EffortTargetCard(scores: scores, record: record, isToday: date == health.today)
            }
            rawTrend(title: "Active Zone Minutes", unit: "min", color: Theme.effort, style: .bars) {
                $0.activeZoneMinutes.map(Double.init)
            }
        }
    }

    private func restorativeText(_ sleep: SleepSummary) -> String? {
        guard let deep = sleep.deepMinutes, let rem = sleep.remMinutes, sleep.minutesAsleep > 0 else { return nil }
        return "\(Int((Double(deep + rem) / Double(sleep.minutesAsleep) * 100).rounded()))% of the night"
    }

    private func efficiencyText(_ sleep: SleepSummary) -> String {
        guard sleep.minutesInBed > 0 else { return "—" }
        return "\(Int((Double(sleep.minutesAsleep) / Double(sleep.minutesInBed) * 100).rounded()))% asleep in bed"
    }

    private func partsCard(title: String, parts: [(String, Double?, Double, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).sectionLabel()
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                let (name, points, maximum, detail) = part
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        if let detail { Text(detail).font(.caption).foregroundStyle(Theme.textSecondary) }
                        Spacer()
                        Text(points.map { "\(Int($0.rounded()))/\(Int(maximum))" } ?? "no data")
                            .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    ProgressBar(fraction: (points ?? 0) / maximum, color: kind.color, height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func rawTrend(title: String, unit: String, color: Color, goal: Double? = nil, style: TrendCard.Style = .line,
                          value: (DayRecord) -> Double?) -> some View {
        let days = health.recentDays(range)
        return TrendCard(title: title, unit: unit, color: color, range: range, goal: goal, style: style,
                         points: days.compactMap { day in
                             value(day.record).map { TrendPoint(date: day.record.date, value: $0, color: color) }
                         })
    }
}
