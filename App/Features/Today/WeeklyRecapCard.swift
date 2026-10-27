import SwiftUI

/// A fixed-size card drawn into an image for the share sheet.
struct WeeklyRecapCard: View {
    let recap: WeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week of \(recap.weekStart.noon.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption.weight(.bold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                Text("Training camp recap").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 12) {
                tile("Recovery", recap.averageRecovery.map(String.init) ?? "—", color: Theme.recoveryGo, caption: "avg")
                tile("Sleep", recap.averageSleepMinutes.map { Format.duration(minutes: $0) } ?? "—", color: Theme.sleep,
                     caption: "avg a night")
            }
            HStack(spacing: 12) {
                tile("Steps", Format.count(recap.steps), color: Theme.effort, caption: "total")
                tile("Zone minutes", "\(recap.activeZoneMinutes)", color: Theme.effort, caption: "total")
            }
            HStack(spacing: 16) {
                Label("\(recap.goalsHit)/\(recap.goalsPossible) goals", systemImage: "target")
                Label("\(recap.challengesDone)/\(recap.challengesTotal) challenges", systemImage: "checkmark.seal.fill")
                Label("\(recap.longestStreak)", systemImage: "flame.fill")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            HStack {
                Label(recap.tier.title, systemImage: "shield.fill")
                    .font(.headline).foregroundStyle(recap.tier.color)
                Spacer()
                Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Connector")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Theme.background)
    }

    private func tile(_ title: String, _ value: String, color: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(Theme.textSecondary)
            Text(value).font(.scoreNumber(28)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// "Share your week": renders the recap card to an image and opens the share sheet.
struct ShareWeekButton: View {
    let recap: WeeklyRecap
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = renderedImage {
            ShareLink(item: image, preview: SharePreview("My training week", image: image)) {
                Label("Share your week", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)
        }
    }

    private var renderedImage: Image? {
        let renderer = ImageRenderer(content: WeeklyRecapCard(recap: recap).environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
