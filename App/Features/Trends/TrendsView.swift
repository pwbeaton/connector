import Charts
import SwiftUI

/// 7, 30, and 90-day charts of Recovery, Sleep, Effort, HRV, and resting heart rate,
/// plus personal records.
struct TrendsView: View {
    @Environment(AppSession.self) private var session
    @State private var range = 30

    private var health: HealthModel { session.health }
    private var start: CivilDate { health.today.adding(days: -(range - 1)) }

    var body: some View {
        let days = Dictionary(health.recentDays(range).map { ($0.record.date, $0) }, uniquingKeysWith: { _, last in last })
        let dates = start.through(health.today)
        PlutoScreen(title: "Trends", subtitle: "\(range) days", startsAtBottom: session.options.startsAtBottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rangeTitle).eyebrow()
                Text("Trends").screenTitle()
            }
            rangePicker.padding(.top, 6)
            ChartCard(title: "Recovery", average: average(dates.compactMap { days[$0]?.scores?.recovery.score.map { Double($0.total) } }),
                      unit: nil, showsAverageKey: true, dates: dates, yAxis: [(100, "100"), (50, "50"), (0, "0")]) {
                BarPlot(values: dates.map { days[$0]?.scores?.recovery.score.map { Double($0.total) } },
                        domain: 0...100, color: Theme.recoveryBar,
                        average: average(dates.compactMap { days[$0]?.scores?.recovery.score.map { Double($0.total) } }))
            }
            .padding(.top, 4)
            sleepCard(dates: dates, days: days)
            ChartCard(title: "Effort", average: average(dates.compactMap { days[$0]?.scores?.effort.map(Double.init) }),
                      unit: nil, showsAverageKey: true, dates: dates,
                      yAxis: [(100, "100"), (60, "60"), (40, "40"), (0, "0")], highlightedAxis: [60, 40]) {
                BarPlot(values: dates.map { days[$0]?.scores?.effort.map(Double.init) },
                        domain: 0...100, color: Theme.effortBar, band: 40...60,
                        average: average(dates.compactMap { days[$0]?.scores?.effort.map(Double.init) }))
            }
            lineCard(title: "HRV", unit: "ms", color: Theme.teal, dates: dates) { days[$0]?.record.hrvMs }
            lineCard(title: "Resting heart rate", unit: "bpm", color: Theme.textSecondary, dates: dates) { days[$0]?.record.restingHeartRate }
            Text("Personal records").sectionHeading().padding(.top, 14)
            RecordsSection(records: health.snapshot.records)
        }
    }

    private var rangeTitle: String {
        let first = start.noon.formatted(.dateTime.month(.abbreviated).day())
        let last = health.today.noon.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(last)"
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach([7, 30, 90], id: \.self) { option in
                let selected = range == option
                Button {
                    withAnimation(.snappy) { range = option }
                } label: {
                    Text("\(option) days")
                        .font(.archivo(15, selected ? .bold : .medium))
                        .foregroundStyle(selected ? Theme.onInverse : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? Theme.inverse : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.controlStroke, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: range)
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func sleepCard(dates: [CivilDate], days: [CivilDate: (record: DayRecord, scores: DayScores?)]) -> some View {
        let hours = dates.map { days[$0]?.record.sleep.map { Double($0.minutesAsleep) / 60 } }
        let present = hours.compactMap { $0 }
        let goal = Double(health.goals.sleepMinutes) / 60
        let low = min(6, (present.min() ?? 6).rounded(.down))
        let high = max(low + 2.5, goal + 0.5, ((present.max() ?? 8) * 2).rounded(.up) / 2)
        let marks = stride(from: Int(low.rounded(.up)), through: Int(high.rounded(.down)), by: 1).map { (Double($0), "\($0)h") }
        return ChartCard(title: "Sleep", average: average(present), unit: "h", decimals: 1, showsAverageKey: false,
                         dates: dates, yAxis: marks.reversed(), domain: low...high,
                         legend: AnyView(SleepLegend(goalMinutes: health.goals.sleepMinutes))) {
            LollipopPlot(values: hours, domain: low...high, goal: goal)
        }
    }

    private func lineCard(title: String, unit: String, color: Color, dates: [CivilDate],
                          value: (CivilDate) -> Double?) -> some View {
        let values = dates.map(value)
        let present = values.compactMap { $0 }
        let low = ((present.min() ?? 0) - 1).rounded(.down), high = ((present.max() ?? 1) + 1).rounded(.up)
        let step = max(1, ((high - low) / 3).rounded())
        let marks = stride(from: high, through: low, by: -step).map { ($0, "\(Int($0))") }
        return ChartCard(title: title, average: average(present), unit: unit, showsAverageKey: true, dates: dates,
                         yAxis: marks, domain: low...high, plotHeight: 96) {
            LinePlot(values: values, domain: low...high, color: color, average: average(present), gridMarks: marks.map(\.0))
        }
    }
}

// MARK: - Chart chrome

/// A trends card: mono title, "avg 60" on the right, a plot with a y-axis column, and dates below.
struct ChartCard<Plot: View>: View {
    let title: String
    let average: Double?
    let unit: String?
    var decimals = 0
    var showsAverageKey = true
    let dates: [CivilDate]
    var yAxis: [(Double, String)]
    var domain: ClosedRange<Double> = 0...100
    var highlightedAxis: [Double] = []
    var legend: AnyView?
    var plotHeight: CGFloat = 110
    @ViewBuilder let plot: Plot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).sectionLabel()
                Spacer()
                if let average {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if showsAverageKey {
                            Line().stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                                .frame(width: 14, height: 2).alignmentGuide(.firstTextBaseline) { _ in 6 }
                        }
                        Text("avg").font(.archivo(13)).foregroundStyle(Theme.textMuted)
                        Text(average.formatted(.number.precision(.fractionLength(decimals))))
                            .font(.archivo(30, .semibold, width: 70)).foregroundStyle(Theme.textPrimary)
                            .lineBox(1, size: 30)
                        if let unit { Text(unit).font(.archivo(13)).foregroundStyle(Theme.textMuted) }
                    }
                }
            }
            if let legend { legend.padding(.top, 6) }
            if average == nil {
                Text("No data in this period.")
                    .font(.archivo(15)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: plotHeight)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    plot.frame(height: plotHeight)
                    GeometryReader { proxy in
                        ForEach(Array(yAxis.enumerated()), id: \.offset) { _, mark in
                            Text(mark.1).font(.mono(10))
                                .foregroundStyle(highlightedAxis.contains(mark.0) ? Theme.effortText : Theme.textMuted)
                                .fixedSize()
                                .position(x: proxy.size.width - 12,
                                          y: proxy.size.height * (1 - (mark.0 - domain.lowerBound) / (domain.upperBound - domain.lowerBound)))
                        }
                    }
                    .frame(width: 26, height: plotHeight)
                }
                .padding(.top, legend == nil ? 16 : 14)
                dateAxis.padding(.top, 8).padding(.trailing, 32)
            }
        }
        .card(padding: EdgeInsets(top: 18, leading: 25, bottom: 18, trailing: 25))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(average.map { "Average \($0.formatted(.number.precision(.fractionLength(decimals)))) \(unit ?? "") over \(dates.count) days" } ?? "No data")
    }

    private var dateAxis: some View {
        let count = dates.count
        let picks = count <= 1 ? [] : [0, count / 4, count / 2, 3 * count / 4]
        return GeometryReader { proxy in
            ForEach(picks, id: \.self) { index in
                let x = proxy.size.width * CGFloat(index) / CGFloat(max(1, count - 1))
                Text(dates[index].noon.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.mono(10)).foregroundStyle(Theme.textMuted).fixedSize()
                    .position(x: index == 0 ? 22 : x, y: 7)
            }
            Text("Today").font(.mono(10, .medium)).foregroundStyle(Theme.textPrimary).fixedSize()
                .position(x: proxy.size.width - 16, y: 7)
        }
        .frame(height: 14)
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct SleepLegend: View {
    let goalMinutes: Int

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(Theme.sleep).frame(width: 8, height: 8)
                Text("Hit \(Format.duration(minutes: goalMinutes)) goal")
            }
            HStack(spacing: 6) {
                Circle().strokeBorder(Theme.sleep, lineWidth: 2).frame(width: 8, height: 8)
                Text("Missed")
            }
        }
        .font(.archivo(12))
        .foregroundStyle(Theme.textMuted)
    }
}

// MARK: - Plots

private func dashedLine(_ y: CGFloat, width: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: y))
    path.addLine(to: CGPoint(x: width, y: y))
    return path
}

/// Daily bars; missing days are gaps, today's bar is ink.
struct BarPlot: View {
    let values: [Double?]
    let domain: ClosedRange<Double>
    let color: Color
    var band: ClosedRange<Double>?
    var average: Double?

    var body: some View {
        Canvas { context, size in
            func y(_ value: Double) -> CGFloat {
                size.height * (1 - CGFloat((value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)))
            }
            if let band {
                context.fill(Path(CGRect(x: 0, y: y(band.upperBound), width: size.width, height: y(band.lowerBound) - y(band.upperBound))),
                             with: .color(Theme.effortTint))
            }
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)), with: .color(Theme.gridLine))
            if band == nil {
                context.fill(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)), with: .color(Theme.gridLine))
            }
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Theme.baseline))
            let count = values.count
            let spacing = count > 1 ? size.width / CGFloat(count) : size.width
            let barWidth = min(14, max(2, spacing * 0.55))
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let x = count > 1 ? (size.width - barWidth) * CGFloat(index) / CGFloat(count - 1) : (size.width - barWidth) / 2
                let height = max(2, size.height - y(value))
                let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                let shape = UnevenRoundedRectangle(topLeadingRadius: min(3, barWidth / 2), bottomLeadingRadius: 1,
                                                   bottomTrailingRadius: 1, topTrailingRadius: min(3, barWidth / 2))
                context.fill(shape.path(in: rect), with: .color(index == count - 1 ? Theme.textPrimary : color))
            }
            if let average {
                context.stroke(dashedLine(y(average), width: size.width), with: .color(Theme.textPrimary.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }
}

/// Nightly sleep: a stem per night with a dot, filled when the goal was hit.
struct LollipopPlot: View {
    let values: [Double?]
    let domain: ClosedRange<Double>
    let goal: Double

    var body: some View {
        Canvas { context, size in
            func y(_ value: Double) -> CGFloat {
                size.height * (1 - CGFloat((min(domain.upperBound, max(domain.lowerBound, value)) - domain.lowerBound)
                                           / (domain.upperBound - domain.lowerBound)))
            }
            var hour = domain.lowerBound.rounded(.up)
            while hour <= domain.upperBound {
                context.fill(Path(CGRect(x: 0, y: y(hour), width: size.width, height: 1)),
                             with: .color(hour == domain.lowerBound ? Theme.baseline : Theme.gridLine))
                hour += 1
            }
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Theme.baseline))
            context.stroke(dashedLine(y(goal), width: size.width), with: .color(Theme.sleep), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            let count = values.count
            let dot: CGFloat = count > 60 ? 4 : 8
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let x = count > 1 ? (size.width - dot) * CGFloat(index) / CGFloat(count - 1) + dot / 2 : size.width / 2
                let top = y(value)
                context.fill(Path(CGRect(x: x - 1, y: top, width: 2, height: size.height - top)), with: .color(Theme.sleepStem))
                let circle = Path(ellipseIn: CGRect(x: x - dot / 2, y: top - dot / 2, width: dot, height: dot))
                let last = index == count - 1
                context.fill(circle, with: .color(value >= goal ? Theme.sleep : Theme.surface))
                context.stroke(Path(ellipseIn: CGRect(x: x - dot / 2 + 1, y: top - dot / 2 + 1, width: dot - 2, height: dot - 2)),
                               with: .color(last ? Theme.textPrimary : Theme.sleep), lineWidth: dot > 4 ? 2 : 1)
            }
        }
    }
}

/// A daily line with a dashed average and a ring on today.
struct LinePlot: View {
    let values: [Double?]
    let domain: ClosedRange<Double>
    let color: Color
    var average: Double?
    var gridMarks: [Double] = []

    var body: some View {
        Canvas { context, size in
            func y(_ value: Double) -> CGFloat {
                4 + (size.height - 8) * (1 - CGFloat((value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)))
            }
            for mark in gridMarks {
                context.fill(Path(CGRect(x: 0, y: y(mark), width: size.width, height: 1)), with: .color(Theme.gridLine))
            }
            if let average {
                context.stroke(dashedLine(y(average), width: size.width), with: .color(Theme.textPrimary.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            let count = values.count
            var path = Path()
            var started = false
            var last: CGPoint?
            for (index, value) in values.enumerated() {
                guard let value else { started = false; continue }
                let point = CGPoint(x: 4 + (size.width - 8) * CGFloat(index) / CGFloat(max(1, count - 1)), y: y(value))
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
                last = point
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            if let last {
                let ring = Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10))
                context.fill(ring, with: .color(Theme.surface))
                context.stroke(ring, with: .color(Theme.textPrimary), lineWidth: 2.5)
            }
        }
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
                        .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                }
            }
            if points.isEmpty {
                Text("No data in this period.")
                    .font(.app(.subheadline)).foregroundStyle(Theme.textSecondary)
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
                        // Monotone curves never overshoot the real values (catmull-rom can).
                        .interpolationMethod(.monotone)
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
        VStack(spacing: 0) {
            ForEach(records) { record in
                HStack(spacing: 14) {
                    Image(systemName: symbol(record.kind))
                        .font(.system(size: 17))
                        .foregroundStyle(tint(record.kind).0)
                        .frame(width: 40, height: 40)
                        .background(tint(record.kind).1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(record.kind.title).font(.archivo(16, .medium)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        UnitNumber(parts: value(record), size: 24, width: 72)
                        Text(record.date.noon.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.mono(11)).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(height: 64)
                .overlay(alignment: .bottom) {
                    if record.id != records.last?.id { Rectangle().fill(Theme.gridLine).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
            if records.isEmpty {
                Text("Records appear after your first synced day.")
                    .font(.archivo(15)).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
        }
        .card(padding: EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    private func value(_ record: PersonalRecord) -> [(value: String, unit: String?)] {
        let value = Int(record.value.rounded())
        switch record.kind {
        case .mostSteps: return [(Format.count(value), nil)]
        case .mostAZM: return [("\(value)", "min")]
        case .longestSleep: return UnitNumber.duration(minutes: value)
        case .highestHRV: return [("\(value)", "ms")]
        case .lowestRestingHR: return [("\(value)", "bpm")]
        case .bestRecovery: return [("\(value)", nil)]
        case .longestStreak: return [("\(value)", value == 1 ? "day" : "days")]
        }
    }

    private func symbol(_ kind: RecordKind) -> String {
        switch kind {
        case .mostSteps: "shoeprints.fill"
        case .mostAZM: "bolt.heart"
        case .longestSleep: "moon"
        case .highestHRV: "waveform.path.ecg"
        case .lowestRestingHR: "heart"
        case .bestRecovery: "battery.100.bolt"
        case .longestStreak: "flame"
        }
    }

    private func tint(_ kind: RecordKind) -> (Color, Color) {
        switch kind {
        case .mostSteps, .mostAZM, .longestStreak: (Theme.effort, Color(light: 0xFBE9DE, dark: 0x3A2418))
        case .longestSleep: (Theme.sleep, Theme.sleepTint)
        case .highestHRV, .bestRecovery: (Theme.teal, Theme.tealTint)
        case .lowestRestingHR: (Theme.textSecondary, Color(light: 0xEDF0F2, dark: 0x1C2A33))
        }
    }
}
