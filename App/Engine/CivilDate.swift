import Foundation

/// A calendar day with no time or time zone, like "2026-10-27".
///
/// Google Health reports daily data by the user's local ("civil") date, so the
/// app keys everything by civil date. Arithmetic uses plain day numbers, which
/// makes it immune to daylight-saving changes and time-zone travel.
nonisolated struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The local date of `date` in `timeZone`.
    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func today(in timeZone: TimeZone = .current, now: Date = .now) -> CivilDate {
        CivilDate(date: now, timeZone: timeZone)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: Day arithmetic

    /// Days since 1970-01-01 (proleptic Gregorian calendar).
    /// Algorithm: Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms".
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    func adding(days: Int) -> CivilDate {
        CivilDate(dayNumber: dayNumber + days)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(until other: CivilDate) -> Int {
        other.dayNumber - dayNumber
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    var isoWeekday: Int {
        // 1970-01-01 was a Thursday (ISO weekday 4).
        let remainder = (dayNumber + 3) % 7
        return (remainder < 0 ? remainder + 7 : remainder) + 1
    }

    /// The Monday that starts this date's week.
    var weekStart: CivilDate {
        adding(days: -(isoWeekday - 1))
    }

    /// A stable number for each week (0 = the week of Monday 2024-01-01), used to
    /// rotate weekly challenges. The server uses the same formula.
    var weekIndex: Int {
        let epoch = CivilDate(year: 2024, month: 1, day: 1).dayNumber
        // Both are Mondays, so the difference is a whole number of weeks.
        let days = weekStart.dayNumber - epoch
        return days >= 0 ? days / 7 : -((-days + 6) / 7)
    }

    /// Every date from `self` through `end`, inclusive.
    func through(_ end: CivilDate) -> [CivilDate] {
        guard end >= self else { return [] }
        return (dayNumber...end.dayNumber).map(CivilDate.init(dayNumber:))
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Encoded as the "YYYY-MM-DD" string, matching Postgres `date` and the API filters.
nonisolated extension CivilDate: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = CivilDate(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(string)")
        }
        self = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
