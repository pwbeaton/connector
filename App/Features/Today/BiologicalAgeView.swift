import Charts
import SwiftUI

extension BiologicalAgeTrend.Direction {
    var color: Color {
        switch self {
        case .improving: Theme.recoveryGo
        case .steady: Theme.recoverySteady
        case .worsening: Theme.recoveryRest
        }
    }

    var symbol: String {
        switch self {
        case .improving: "arrow.down.right"
        case .steady: "arrow.right"
        case .worsening: "arrow.up.right"
        }
    }
}

nonisolated enum AgeFormat {
    /// "27.4"
    static func age(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// "3.1 years younger than your age" / "0.4 years older than your age".
    static func difference(_ difference: Double) -> String {
        let years = abs(difference)
        if years < 0.05 { return "Right at your age" }
        let amount = years.formatted(.number.precision(.fractionLength(1)))
        return "\(amount) \(years == 1 ? "year" : "years") \(difference < 0 ? "younger" : "older") than your age"
    }

    /// "0.6 years younger than 4 weeks ago".
    static func trend(_ trend: BiologicalAgeTrend, on date: CivilDate) -> String {
        let weeks = max(1, trend.since.days(until: date) / 7)
        let span = weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        let amount = abs(trend.change).formatted(.number.precision(.fractionLength(1)))
        switch trend.direction {
        case .steady: return "About the same as \(span)"
        case .improving: return "\(amount) years younger than \(span)"
        case .worsening: return "\(amount) years older than \(span)"
        }
    }
}

// MARK: - Card on Today

struct BiologicalAgeCard: View {
    let result: BiologicalAgeResult?
    let trend: BiologicalAgeTrend?
    let history: [BiologicalAgeResult]
    let hasAge: Bool
    let daysOfData: Int

    private var color: Color { trend?.direction.color ?? Theme.textPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Biological age").sectionLabel()
                Spacer()
                CardChevron()
            }
            if let result {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(AgeFormat.age(result.biologicalAge))
                                .font(.scoreNumber(48))
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                            Text("vs \(result.chronologicalAge) actual")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(AgeFormat.difference(result.difference))
                            .font(.subheadline).foregroundStyle(Theme.textPrimary)
                    }
                    Spacer(minLength: 0)
                    if history.count >= 2 {
                        sparkline.frame(width: 96, height: 44)
                    }
                }
                if let trend {
                    Label(AgeFormat.trend(trend, on: result.date), systemImage: trend.direction.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(trend.direction.color)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(trend.direction.color.opacity(0.14), in: Capsule())
                } else {
                    Text("Your trend appears after another week of data.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } else if !hasAge {
                placeholder(symbol: "person.text.rectangle",
                            text: "Add your age to see your biological age: how old your body acts based on fitness, activity, and sleep.")
            } else {
                placeholder(symbol: "hourglass",
                            text: "Biological age needs \(BiologicalAge.minimumDays) days of data. You have \(min(daysOfData, BiologicalAge.minimumDays)) so far.")
            }
        }
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(result != nil && trend != nil ? 0.35 : 0), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func placeholder(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.effort).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sparkline: some View {
        Chart(history, id: \.date) { point in
            LineMark(x: .value("Day", point.date.noon), y: .value("Age", point.biologicalAge))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: sparkDomain)
        .accessibilityHidden(true)
    }

    private var sparkDomain: ClosedRange<Double> {
        let values = history.map(\.biologicalAge)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max(0.3, (high - low) * 0.25)
        return (low - pad)...(high + pad)
    }
}

// MARK: - Detail

struct BiologicalAgeDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let date: CivilDate

    private var health: HealthModel { session.health }

    var body: some View {
        let result = health.biologicalAge(on: date)
        let trend = health.biologicalAgeTrend(on: date)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result {
                        summary(result, trend: trend)
                        historyCard(result)
                        contributorsCard(result)
                    } else {
                        Text(health.chronologicalAge == nil
                             ? "Add your age below to see your biological age."
                             : "Biological age needs \(BiologicalAge.minimumDays) days of data in the last \(BiologicalAge.windowDays). Keep wearing your Fitbit Air.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .card()
                    }
                    settingsCard
                    methodCard
                    Text("An estimate from population research to guide habits, not a medical test.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Biological age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func summary(_ result: BiologicalAgeResult, trend: BiologicalAgeTrend?) -> some View {
        let color = trend?.direction.color ?? Theme.textPrimary
        return VStack(spacing: 8) {
            Text(AgeFormat.age(result.biologicalAge))
                .font(.scoreNumber(72))
                .foregroundStyle(color)
            Text("Biological age · you're \(result.chronologicalAge)")
                .sectionLabel()
            Text(AgeFormat.difference(result.difference))
                .font(.headline).foregroundStyle(Theme.textPrimary)
            if let trend {
                Label("\(trend.direction.title): \(AgeFormat.trend(trend, on: date).lowercasedFirst)",
                      systemImage: trend.direction.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trend.direction.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func historyCard(_ result: BiologicalAgeResult) -> some View {
        let points = health.biologicalAges.values.filter { $0.date <= date }.sorted { $0.date < $1.date }
        let values = points.map(\.biologicalAge) + [Double(result.chronologicalAge)]
        let low = (values.min() ?? 0) - 1, high = (values.max() ?? 1) + 1
        return VStack(alignment: .leading, spacing: 12) {
            Text("History").sectionLabel()
            Chart {
                ForEach(points, id: \.date) { point in
                    AreaMark(x: .value("Day", point.date.noon), yStart: .value("Base", low), yEnd: .value("Age", point.biologicalAge))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.effort.opacity(0.25), Theme.effort.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", point.date.noon), y: .value("Age", point.biologicalAge))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.effort)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                RuleMark(y: .value("Your age", Double(result.chronologicalAge)))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Your age \(result.chronologicalAge)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
            }
            .chartYScale(domain: low...high)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
            Text("Each point uses the \(BiologicalAge.windowDays) days before it, so it moves slowly and rewards steady habits.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func contributorsCard(_ result: BiologicalAgeResult) -> some View {
        let maxYears = max(1, result.contributors.compactMap { $0.years.map(abs) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text("What's moving it").sectionLabel()
            ForEach(result.contributors) { contributor in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: contributor.kind.symbol)
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contributor.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("\(contributor.value) · \(contributor.reference)")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(yearsText(contributor.years))
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(yearsColor(contributor.years))
                    }
                    if let years = contributor.years {
                        DivergingBar(fraction: years / maxYears, color: yearsColor(years))
                            .padding(.leading, 32)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if contributor.id != result.contributors.last?.id { Divider() }
            }
        }
        .card()
    }

    private func yearsText(_ years: Double?) -> String {
        guard let years else { return "—" }
        if abs(years) < 0.05 { return "0.0 yrs" }
        return (years > 0 ? "+" : "−") + abs(years).formatted(.number.precision(.fractionLength(1))) + " yrs"
    }

    private func yearsColor(_ years: Double?) -> Color {
        guard let years, abs(years) >= 0.05 else { return Theme.textSecondary }
        return years < 0 ? Theme.recoveryGo : Theme.recoveryRest
    }

    // MARK: Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your details").sectionLabel()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Age").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(ageSource).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let age = health.chronologicalAge {
                    Stepper(value: Binding(get: { age }, set: { save(age: $0) }), in: 18...100) {
                        Text("\(age)").font(.headline).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    }
                    .fixedSize()
                } else {
                    Button("Add age") { save(age: 30) }.font(.subheadline.weight(.semibold))
                }
            }
            if health.state.ageOverride != nil, let profileAge = health.profileAge {
                Button("Use my Google Health age (\(profileAge))") {
                    Task { await health.updateBiologicalAgeSettings(ageOverride: nil, sex: health.sex) }
                }
                .font(.footnote.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Fitness norms").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Picker("Fitness norms", selection: Binding(get: { health.sex }, set: { sex in
                    Task { await health.updateBiologicalAgeSettings(ageOverride: health.state.ageOverride, sex: sex) }
                })) {
                    Text("Average").tag(BiologicalSex?.none)
                    ForEach(BiologicalSex.allCases, id: \.self) { Text($0.title).tag(BiologicalSex?.some($0)) }
                }
                .pickerStyle(.segmented)
                Text("VO₂ max and resting heart rate norms differ between men and women. Google Health doesn't share this, so it's set here and stays on this iPhone.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var ageSource: String {
        if health.state.ageOverride != nil { return "Set by you" }
        if health.profileAge != nil { return "From your Google Health profile" }
        return "Not set"
    }

    private func save(age: Int) {
        Task { await health.updateBiologicalAgeSettings(ageOverride: age, sex: health.sex) }
    }

    // MARK: Method

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it's calculated").sectionLabel()
            Text("Large studies tie each of these metrics to the risk of dying from any cause. Risk rises about 10% with each year of adult age, so a metric's extra or reduced risk converts into years (the method behind WHOOP Age, heart age, and lung age). Your biological age is your age plus those years, using your last \(BiologicalAge.windowDays) days. Overlapping pairs (VO₂ max and resting heart rate; steps and Active Zone Minutes) count at \(Int(BiologicalAge.overlapShare * 100))% so the same fitness isn't counted twice. HRV isn't used because it varies too much between people to compare against population norms.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(Self.sources.enumerated()), id: \.offset) { _, source in
                    Link(destination: source.url) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "doc.text").font(.caption)
                            Text(source.title).font(.caption).multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .card()
    }

    static let sources: [(title: String, url: URL)] = [
        ("Method: WHOOP Healthspan white paper (2025)", URL(string: "https://www.whoop.com/us/en/thelocker/Healthspan-Data-Meets-Longevity")!),
        ("VO₂ max: Kodama et al., JAMA 2009", URL(string: "https://doi.org/10.1001/jama.2009.681")!),
        ("Resting heart rate: Zhang et al., CMAJ 2016", URL(string: "https://doi.org/10.1503/cmaj.150535")!),
        ("Steps: Paluch et al., Lancet Public Health 2022", URL(string: "https://doi.org/10.1016/S2468-2667(21)00302-9")!),
        ("Exercise minutes: Arem et al., JAMA Intern Med 2015", URL(string: "https://doi.org/10.1001/jamainternmed.2015.0533")!),
        ("Sleep duration: Cappuccio et al., Sleep 2010", URL(string: "https://doi.org/10.1093/sleep/33.5.585")!),
        ("Sleep regularity: Windred et al., Sleep 2024", URL(string: "https://doi.org/10.1093/sleep/zsad253")!),
    ]
}

/// A bar that grows left (negative, good) or right (positive) from the middle.
struct DivergingBar: View {
    /// −1…1
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let width = max(4, half * min(1, abs(fraction)))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Rectangle().fill(Theme.textSecondary.opacity(0.4)).frame(width: 1).offset(x: half)
                Capsule().fill(color)
                    .frame(width: width)
                    .offset(x: fraction < 0 ? half - width : half)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

extension String {
    /// "About the same" → "about the same".
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
