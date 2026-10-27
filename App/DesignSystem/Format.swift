import Foundation

/// How numbers and times read on screen.
nonisolated enum Format {
    /// "7h 32m" (or "45m").
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "8,423" in the user's locale.
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// "4.2 mi" or "6.8 km".
    static func distance(meters: Double, metric: Bool = Locale.current.measurementSystem == .metric) -> String {
        let value = metric ? meters / 1000 : meters / 1609.344
        return value.formatted(.number.precision(.fractionLength(1))) + (metric ? " km" : " mi")
    }

    /// "6:40 AM" for a minute of the day.
    static func clock(minuteOfDay: Int) -> String {
        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        let date = Calendar(identifier: .gregorian).date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "just now", "4 min ago", "3 h ago", "2 days ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60): return "\(minutes / 60) h ago"
        default:
            let days = minutes / (24 * 60)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    /// "Tuesday, Oct 27".
    static func dayTitle(_ date: CivilDate) -> String {
        date.noon.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "Tue" for chart axes and day pickers.
    static func weekdayShort(_ date: CivilDate) -> String {
        date.noon.formatted(.dateTime.weekday(.abbreviated))
    }

    /// A leaderboard value with its unit.
    static func leaderboard(_ value: Double, metric: LeaderboardMetric) -> String {
        switch metric {
        case .effort: "\(Int(value.rounded())) pts"
        case .steps: count(Int(value.rounded()))
        case .azm: "\(Int(value.rounded())) min"
        case .averageSleep: duration(minutes: Int(value.rounded()))
        case .longNights: Int(value) == 1 ? "1 night" : "\(Int(value)) nights"
        }
    }
}

extension CivilDate {
    /// Noon on this date in the current time zone, for formatting (noon never falls in a DST gap).
    nonisolated var noon: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? .now
    }
}
