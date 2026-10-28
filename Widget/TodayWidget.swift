import SwiftUI
import WidgetKit

// Home Screen widgets: today's Recovery (small) and Recovery / Sleep / Effort (medium).
// The app writes WidgetSnapshot after every sync and asks WidgetKit to reload;
// the widget only reads that file, so it never needs network access or tokens.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True for the widget gallery, before the app has synced.
    var isSample = false

    /// Numbers from an earlier day: shown dimmed with "Open to sync".
    var isStale: Bool {
        snapshot.date != Self.civilDate(date)
    }

    static func civilDate(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample, isSample: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(currentEntry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // The app reloads the widget after each sync; this hourly refresh only keeps "stale" honest.
        let entry = currentEntry(preview: false)
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(3600))))
    }

    private func currentEntry(preview: Bool) -> TodayEntry {
        if let snapshot = WidgetSnapshotFile.load() {
            return TodayEntry(date: .now, snapshot: snapshot)
        }
        return TodayEntry(date: .now, snapshot: .sample, isSample: preview)
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .opacity(entry.isStale && !entry.isSample ? 0.55 : 1)
        .containerBackground(for: .widget) { Theme.background }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recovery").font(.app(.caption2, .bold)).textCase(.uppercase).foregroundStyle(Theme.textSecondary)
                Spacer()
                streak
            }
            Spacer(minLength: 0)
            WidgetRing(value: snapshot.recovery, color: recoveryColor, lineWidth: 9,
                       placeholder: snapshot.calibratingNights.map { "\($0)/7" } ?? "—")
                .frame(width: 84, height: 84)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(footer).font(.app(.caption2, .semibold)).foregroundStyle(recoveryColor)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.isStale && !entry.isSample ? "Open to sync" : "Today")
                    .font(.app(.caption, .bold)).textCase(.uppercase).foregroundStyle(Theme.textSecondary)
                Spacer()
                streak
            }
            HStack(spacing: 12) {
                column("Recovery", value: snapshot.recovery, color: recoveryColor,
                       placeholder: snapshot.calibratingNights.map { "\($0)/7" } ?? "—")
                column("Sleep", value: snapshot.sleep, color: Theme.sleep)
                column("Effort", value: snapshot.effort, color: Theme.effort)
            }
            Text("Effort target \(snapshot.effortTargetLow)–\(snapshot.effortTargetHigh)"
                 + (snapshot.steps.map { " · \($0.formatted()) steps" } ?? ""))
                .font(.app(.caption2)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func column(_ title: String, value: Int?, color: Color, placeholder: String = "—") -> some View {
        VStack(spacing: 4) {
            WidgetRing(value: value, color: color, lineWidth: 7, placeholder: placeholder)
                .frame(width: 62, height: 62)
            Text(title).font(.app(.caption2, .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var streak: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill").foregroundStyle(snapshot.streakDays > 0 ? Theme.recoverySteady : Theme.textSecondary)
            Text("\(snapshot.streakDays)").monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
        .font(.app(.caption, .bold))
    }

    private var recoveryColor: Color {
        switch snapshot.recoveryBand {
        case "go": Theme.recoveryGo
        case "steady": Theme.recoverySteady
        case "recover": Theme.recoveryRest
        default: Theme.textSecondary
        }
    }

    private var footer: String {
        if entry.isStale && !entry.isSample { return "Open to sync" }
        switch snapshot.recoveryBand {
        case "go": return "GO · target \(snapshot.effortTargetLow)–\(snapshot.effortTargetHigh)"
        case "steady": return "STEADY · target \(snapshot.effortTargetLow)–\(snapshot.effortTargetHigh)"
        case "recover": return "RECOVER · keep it light"
        default: return snapshot.calibratingNights == nil ? "No data yet" : "Calibrating"
        }
    }
}

/// A score ring without animation (widgets are static images).
struct WidgetRing: View {
    let value: Int?
    let color: Color
    let lineWidth: CGFloat
    var placeholder = "—"

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Double(value ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value.map(String.init) ?? placeholder)
                .font(.scoreNumber(value == nil ? 14 : 22))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .padding(lineWidth)
        }
    }
}

@main
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your Recovery, Sleep, and Effort at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, isSample: true)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, isSample: true)
}
