import Charts
import SwiftUI

extension SleepDebt.Level {
    var color: Color {
        switch self {
        case .low: Theme.recoveryGo
        case .moderate: Theme.recoverySteady
        case .high: Theme.recoveryRest
        }
    }
}

nonisolated enum BedtimeFormat {
    /// "20 min earlier than usual", "1h 5m later than usual", "Right at your usual time".
    static func shift(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if abs(minutes) < 10 { return "Right at your usual time" }
        return "\(Format.duration(minutes: abs(minutes))) \(minutes < 0 ? "earlier" : "later") than usual"
    }

    static func shiftSymbol(_ minutes: Int?) -> String {
        guard let minutes, abs(minutes) >= 10 else { return "equal" }
        return minutes < 0 ? "arrowtriangle.backward.fill" : "arrowtriangle.forward.fill"
    }
}

// MARK: - Tonight (on Today)

/// Tonight's bedtime with sleep debt baked in, and whether it's earlier or later than usual.
struct TonightCard: View {
    let plan: BedtimePlan
    let debt: SleepDebt?

    var body: some View {
        // One row when everything fits at full size; otherwise sleep debt drops to its own row.
        // Nothing is ever truncated or shrunk.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                moon
                bedtime(wrapsShift: false)
                Spacer(minLength: 12)
                if let debt { debtColumn(debt) }
                CardChevron()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    moon
                    bedtime(wrapsShift: true)
                    Spacer(minLength: 8)
                    CardChevron()
                }
                if let debt {
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Sleep debt").sectionLabel().fixedSize()
                        Spacer(minLength: 8)
                        Text(debtText(debt))
                            .font(.headline).monospacedDigit()
                            .foregroundStyle(debt.level.color)
                            .fixedSize()
                        Text(debt.level.title).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize()
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var moon: some View {
        Image(systemName: "moon.stars.fill")
            .font(.title3)
            .foregroundStyle(Theme.sleep)
            .frame(width: 44, height: 44)
            .background(Theme.sleep.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }

    private func bedtime(wrapsShift: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Tonight · bed by").sectionLabel().fixedSize()
            Text(Format.clock(minuteOfDay: plan.bedtime))
                .font(.scoreNumber(26))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
            if let shift = BedtimeFormat.shift(plan.shiftFromUsual) {
                Label(shift, systemImage: BedtimeFormat.shiftSymbol(plan.shiftFromUsual))
                    .labelStyle(TightLabelStyle())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.sleep)
                    .fixedSize(horizontal: !wrapsShift, vertical: true)
            }
        }
    }

    private func debtColumn(_ debt: SleepDebt) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("Sleep debt").sectionLabel()
            Text(debtText(debt))
                .font(.headline).monospacedDigit()
                .foregroundStyle(debt.level.color)
            Text(debt.level.title).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .fixedSize()
    }

    private func debtText(_ debt: SleepDebt) -> String {
        debt.minutes == 0 ? "None" : Format.duration(minutes: debt.minutes)
    }
}

/// A label with the icon close to the text, for small inline captions.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}

// MARK: - Sleep debt (in the Sleep detail)

struct SleepDebtCard: View {
    let debt: SleepDebt
    /// Only for today: tonight's bedtime.
    let plan: BedtimePlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sleep debt").sectionLabel()
                Spacer()
                Text(debt.level.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(debt.level.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(debt.level.color.opacity(0.15), in: Capsule())
            }
            Text(debt.minutes == 0 ? "None" : Format.duration(minutes: debt.minutes))
                .font(.scoreNumber(40))
                .foregroundStyle(debt.level.color)
            Text("What you owe against your \(Format.duration(minutes: debt.goalMinutes)) sleep goal over the last \(ScoreTuning.sleepDebtNights) nights. Recent nights count more, and nights over your goal pay it down. Under 5 hours is the range to aim for.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chart.frame(height: 120)
            if let plan {
                Divider()
                planView(plan)
            }
            Text("One hour of sleep debt takes about four nights of extra sleep to repay (Kitamura et al., Scientific Reports 2016), so the plan adds a little each night and keeps your wake time fixed.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var chart: some View {
        Chart {
            ForEach(debt.nights) { night in
                BarMark(x: .value("Night", night.date.noon, unit: .day),
                        y: .value("Versus goal", Double(night.balanceMinutes) / 60))
                    .foregroundStyle(night.balanceMinutes < 0 ? Theme.recoveryRest.opacity(0.8) : Theme.sleep)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Goal", 0))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text(hours == 0 ? "goal" : "\(hours > 0 ? "+" : "")\(hours.formatted(.number.precision(.fractionLength(0...1))))h") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .accessibilityLabel("Each night against your sleep goal")
    }

    private func planView(_ plan: BedtimePlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tonight").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Bed by \(Format.clock(minuteOfDay: plan.bedtime))")
                    .font(.headline).monospacedDigit().foregroundStyle(Theme.sleep)
            }
            Text(planText(plan))
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planText(_ plan: BedtimePlan) -> String {
        var parts: [String] = []
        let extra = plan.extraMinutes > 0 ? ", plus \(Format.duration(minutes: plan.extraMinutes)) to pay down debt" : ""
        parts.append("Wake at your usual \(Format.clock(minuteOfDay: plan.wakeTime)) with your full \(Format.duration(minutes: debt.goalMinutes))\(extra).")
        if let shift = BedtimeFormat.shift(plan.shiftFromUsual) { parts.append(shift + ".") }
        if plan.isEasedIn {
            parts.append("A full catch-up would mean bed by \(Format.clock(minuteOfDay: plan.idealBedtime)), but your body clock only shifts about an hour a day, so start here and move earlier over the next few nights.")
        }
        return parts.joined(separator: " ")
    }
}
