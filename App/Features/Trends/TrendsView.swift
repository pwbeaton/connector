import Charts
import SwiftUI

/// 7, 30, and 90-day charts of every score and the raw numbers behind them, plus personal records.
struct TrendsView: View {
    @Environment(AppSession.self) private var session
    @State private var range = 30

    private var health: HealthModel { session.health }

    var body: some View {
        let days = health.recentDays(range)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trends").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)

                TrendCard(title: "Recovery", unit: "", color: Theme.recoveryGo, range: range, domain: 0...100,
                          points: days.compactMap { day in
                              day.scores?.recovery.score.map {
                                  TrendPoint(date: day.record.date, value: Double($0.total), color: $0.band.color)
                              }
                          })
                TrendCard(title: "Sleep", unit: "h", color: Theme.sleep, range: range, goal: Double(health.goals.sleepMinutes) / 60,
                          points: days.compactMap { day in
                              day.record.sleep.map {
                                  TrendPoint(date: day.record.date, value: Double($0.minutesAsleep) / 60, color: Theme.sleep)
                              }
                          })
                TrendCard(title: "Effort", unit: "", color: Theme.effort, range: range, domain: 0...100,
                          points: days.compactMap { day in
                              day.scores?.effort.map { TrendPoint(date: day.record.date, value: Double($0), color: Theme.effort) }
                          })
                TrendCard(title: "Steps", unit: "", color: Theme.effort, range: range, goal: Double(health.goals.steps),
                          points: days.compactMap { day in
                              day.record.steps.map { TrendPoint(date: day.record.date, value: Double($0), color: Theme.effort) }
                          })
                TrendCard(title: "HRV", unit: "ms", color: Theme.recoveryGo, range: range, style: .line,
                          points: days.compactMap { day in
                              day.record.hrvMs.map { TrendPoint(date: day.record.date, value: $0, color: Theme.recoveryGo) }
                          })
                TrendCard(title: "Resting heart rate", unit: "bpm", color: Theme.recoveryRest, range: range, style: .line,
                          points: days.compactMap { day in
                              day.record.restingHeartRate.map {
                                  TrendPoint(date: day.record.date, value: $0, color: Theme.recoveryRest)
                              }
                          })
                RecordsSection(records: health.snapshot.records)
            }
            .padding(Theme.screenPadding)
        }
        .defaultScrollAnchor(session.options.startsAtBottom ? .bottom : .top)
        .background(Theme.background.ignoresSafeArea())
    }
}

struct TrendPoint: Identifiable {
    let date: CivilDate
    let value: Double
    let color: Color

    var id: CivilDate { date }
}

/// One metric over time: the average on top, a chart below. Missing days are gaps, never zeros.
struct TrendCard: View {
    enum Style { case bars, line }

    let title: String
    let unit: String
    let color: Color
    let range: Int
    var domain: ClosedRange<Double>?
    var goal: Double?
    var style = Style.bars
    let points: [TrendPoint]

    private var average: Double? {
        points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).sectionLabel()
                Spacer()
                if let average {
                    Text("avg \(formatted(average))\(unit.isEmpty ? "" : " \(unit)")")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                }
            }
            if points.isEmpty {
                Text("No data in this period.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart.frame(height: 150)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(average.map { "Average \(formatted($0)) \(unit) over \(range) days" } ?? "No data")
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                if style == .bars {
                    BarMark(x: .value("Day", point.date.noon, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(point.color)
                        .cornerRadius(range > 30 ? 1 : 3)
                } else {
                    LineMark(x: .value("Day", point.date.noon, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                    if range <= 30 {
                        PointMark(x: .value("Day", point.date.noon, unit: .day), y: .value(title, point.value))
                            .foregroundStyle(color)
                            .symbolSize(18)
                    }
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTicks) { _ in
                AxisValueLabel(format: range == 7 ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day())
            }
        }
    }

    /// Every day for a week, else evenly spaced dates that stop short of the right edge (so no label is cut off).
    private var xTicks: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let step = range == 7 ? 1 : (range == 30 ? 7 : 21)
        return stride(from: 0, through: first.days(until: last), by: step)
            .map { first.adding(days: $0) }
            .filter { range == 7 || $0.days(until: last) >= step / 2 }
            .map(\.noon)
    }

    private var yDomain: ClosedRange<Double> {
        if let domain { return domain }
        let values = points.map(\.value) + (goal.map { [$0] } ?? [])
        let low = values.min() ?? 0, high = values.max() ?? 1
        if style == .line {
            let pad = max(1, (high - low) * 0.2)
            return (low - pad)...(high + pad)
        }
        return 0...(high * 1.1)
    }

    private func formatted(_ value: Double) -> String {
        value >= 1000 ? Format.count(Int(value.rounded())) : value.formatted(.number.precision(.fractionLength(value < 20 ? 1 : 0)))
    }
}

struct RecordsSection: View {
    let records: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Personal records")
            VStack(spacing: 0) {
                ForEach(records) { record in
                    HStack {
                        Image(systemName: symbol(record.kind)).foregroundStyle(Theme.gold).frame(width: 28)
                        Text(record.kind.title).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(value(record)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text(record.date.noon.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    if record.id != records.last?.id { Divider() }
                }
                if records.isEmpty {
                    Text("Records appear after your first synced day.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card()
        }
    }

    private func value(_ record: PersonalRecord) -> String {
        let value = Int(record.value.rounded())
        switch record.kind {
        case .mostSteps: return Format.count(value)
        case .mostAZM: return "\(value) min"
        case .longestSleep: return Format.duration(minutes: value)
        case .highestHRV: return "\(value) ms"
        case .lowestRestingHR: return "\(value) bpm"
        case .bestRecovery: return "\(value)"
        case .longestStreak: return value == 1 ? "1 day" : "\(value) days"
        }
    }

    private func symbol(_ kind: RecordKind) -> String {
        switch kind {
        case .mostSteps: "figure.walk"
        case .mostAZM: "bolt.heart.fill"
        case .longestSleep: "bed.double.fill"
        case .highestHRV: "waveform.path.ecg"
        case .lowestRestingHR: "heart.fill"
        case .bestRecovery: "arrow.up.heart.fill"
        case .longestStreak: "flame.fill"
        }
    }
}
