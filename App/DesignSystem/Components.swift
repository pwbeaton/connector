import SwiftUI

extension EnvironmentValues {
    /// False in screenshot mode, so captures show final values instead of mid-animation.
    @Entry var animatesScores: Bool = true
}

extension RecoveryBand {
    var color: Color {
        switch self {
        case .go: Theme.recoveryGo
        case .steady: Theme.recoverySteady
        case .recover: Theme.recoveryRest
        }
    }

    /// Pill background behind the band name.
    var tint: Color {
        self == .recover ? Theme.effortTint : Theme.tealTint
    }

    /// Pill text color.
    var textColor: Color {
        self == .recover ? Theme.effortText : Theme.tealDeep
    }

    /// One line of coaching for the day.
    var advice: String {
        switch self {
        case .go: "You're primed. A good day to push hard."
        case .steady: "Solid base. Train, but don't empty the tank."
        case .recover: "Your body is asking for rest. Keep it light."
        }
    }
}

extension Tier {
    var color: Color {
        switch self {
        case .rookie: Theme.textFaint
        case .bronze: Theme.bronze
        case .silver: Theme.silver
        case .gold: Theme.gold
        case .platinum: Theme.platinum
        case .elite: Theme.effort
        }
    }
}

/// A ring that fills to `value` out of 100, with the number in the middle.
struct ScoreDial: View {
    let value: Int?
    let color: Color
    var size: CGFloat = 200
    var lineWidth: CGFloat = 16
    /// Small text under the number, e.g. "RECOVERY".
    var label: String?
    /// Shown instead of a number when `value` is nil, e.g. "4/7".
    var placeholder = "—"

    @Environment(\.animatesScores) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var target: Double { Double(value ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: lineWidth * 0.6)
            VStack(spacing: size * 0.01) {
                Text(value.map(String.init) ?? placeholder)
                    .font(.scoreNumber(size * (value == nil ? 0.2 : 0.3)))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                if let label {
                    Text(label).sectionLabel()
                }
            }
            .padding(lineWidth)
        }
        .frame(width: size, height: size)
        .onAppear { update(animated: true) }
        .onChange(of: value) { update(animated: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Score")
        .accessibilityValue(value.map { "\($0) out of 100" } ?? placeholder)
    }

    private func update(animated: Bool) {
        if animated && animates && !reduceMotion {
            withAnimation(.spring(duration: 1.1, bounce: 0.15)) { shown = target }
        } else {
            shown = target
        }
    }
}

/// A thin rounded progress bar.
struct ProgressBar: View {
    let fraction: Double
    var color: Color = Theme.effort
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule().fill(color)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Effort so far on a 0–100 track, with today's target range marked.
struct EffortTrack: View {
    let effort: Int?
    let target: ClosedRange<Int>

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.effort.opacity(0.14))
                Capsule()
                    .fill(Theme.effort.opacity(0.35))
                    .frame(width: width * Double(target.upperBound - target.lowerBound) / 100)
                    .offset(x: width * Double(target.lowerBound) / 100)
                Capsule().fill(Theme.effort)
                    .frame(width: max(12, width * Double(effort ?? 0) / 100))
                    .opacity(effort == nil ? 0 : 1)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel("Effort \(effort ?? 0) of 100, target \(target.lowerBound) to \(target.upperBound)")
    }
}

/// A mono label over a condensed number, e.g. "HRV / 52 ms".
struct StatPill: View {
    let title: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundStyle(Theme.textMuted)
            Text(value).font(.archivo(28, .semibold, width: 72)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A section heading with an optional mono note on the right ("Leaderboard … THIS WEEK").
struct SectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).sectionHeading()
            Spacer()
            if let trailing {
                Text(trailing).font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.top, 14)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "▼ 8 vs yesterday": the arrow carries the color, the text stays quiet.
struct ChangeLabel: View {
    let change: Int?
    var caption = "vs yesterday"
    var tint: Color?

    var body: some View {
        if let change {
            HStack(spacing: 5) {
                if change != 0 {
                    DeltaArrow(down: change < 0, color: color(change))
                }
                Text(change == 0 ? "Same \(caption)" : "\(abs(change)) \(caption)")
            }
            .font(.archivo(13))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(change == 0 ? "Same as yesterday" : "\(change > 0 ? "Up" : "Down") \(abs(change)) \(caption)")
        }
    }

    private func color(_ change: Int) -> Color {
        if let tint { return tint }
        return change > 0 ? Theme.teal : Theme.effort
    }
}

/// Cards that open a detail screen shrink a touch while pressed.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

/// The small chevron in a tappable card's corner.
struct CardChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
            .accessibilityHidden(true)
    }
}

/// A full-width notice, e.g. "Reconnect Fitbit" or "You're offline".
struct Banner: View {
    let symbol: String
    let message: String
    var color: Color = Theme.teal
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.system(size: 16, weight: .medium))
            Text(message).font(.archivo(14)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.archivo(14, .semibold)).foregroundStyle(Theme.onInverse)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Theme.inverse, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: action == nil ? 16 : 4))
        .frame(minHeight: 52)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.controlStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
