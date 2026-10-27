import Foundation
import Testing
@testable import App

struct CivilDateTests {
    @Test func parsesAndFormats() {
        #expect(CivilDate("2026-03-02") == monday)
        #expect(monday.description == "2026-03-02")
        #expect(CivilDate(year: 2026, month: 1, day: 5).description == "2026-01-05")
    }

    @Test func rejectsMalformedStrings() {
        #expect(CivilDate("2026-13-01") == nil)
        #expect(CivilDate("2026/03/02") == nil)
        #expect(CivilDate("yesterday") == nil)
    }

    @Test func dayNumberMatchesTheUnixEpoch() {
        #expect(CivilDate(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(monday.dayNumber == 20514)
    }

    @Test func dayNumberRoundTripsAcrossLeapYears() {
        let start = CivilDate(year: 2023, month: 12, day: 25)
        for offset in 0..<800 {
            let date = start.adding(days: offset)
            #expect(CivilDate(dayNumber: date.dayNumber) == date)
        }
        #expect(CivilDate(year: 2024, month: 2, day: 28).adding(days: 1) == CivilDate(year: 2024, month: 2, day: 29))
        #expect(CivilDate(year: 2026, month: 2, day: 28).adding(days: 1) == CivilDate(year: 2026, month: 3, day: 1))
    }

    @Test func addsAcrossMonthAndYearBoundaries() {
        #expect(CivilDate(year: 2026, month: 12, day: 31).adding(days: 1) == CivilDate(year: 2027, month: 1, day: 1))
        #expect(monday.adding(days: -2) == CivilDate(year: 2026, month: 2, day: 28))
        #expect(monday.days(until: monday.adding(days: 10)) == 10)
    }

    @Test func daylightSavingDoesNotShiftDays() {
        // Clocks jump on Sunday 2026-03-08 in the US; civil days are unaffected.
        let saturday = CivilDate(year: 2026, month: 3, day: 7)
        #expect(saturday.adding(days: 1) == CivilDate(year: 2026, month: 3, day: 8))
        #expect(saturday.adding(days: 2) == CivilDate(year: 2026, month: 3, day: 9))
    }

    @Test func isoWeekdaysAndWeekStarts() {
        #expect(monday.isoWeekday == 1)
        #expect(CivilDate(year: 2026, month: 10, day: 27).isoWeekday == 2)
        #expect(CivilDate(year: 2026, month: 3, day: 8).isoWeekday == 7)
        #expect(CivilDate(year: 2026, month: 3, day: 8).weekStart == monday)
        #expect(monday.weekStart == monday)
    }

    @Test func weekIndexCountsFromJanuary2024() {
        #expect(CivilDate(year: 2024, month: 1, day: 1).weekIndex == 0)
        #expect(CivilDate(year: 2024, month: 1, day: 7).weekIndex == 0)
        #expect(CivilDate(year: 2024, month: 1, day: 8).weekIndex == 1)
        #expect(CivilDate(year: 2023, month: 12, day: 31).weekIndex == -1)
        #expect(monday.weekIndex == 113)
    }

    @Test func throughIsInclusive() {
        #expect(monday.through(monday.adding(days: 2)).count == 3)
        #expect(monday.through(monday).count == 1)
        #expect(monday.through(monday.adding(days: -1)).isEmpty)
    }

    @Test func encodesAsAPlainDateString() throws {
        let data = try JSONEncoder().encode(["date": monday])
        #expect(String(decoding: data, as: UTF8.self) == #"{"date":"2026-03-02"}"#)
        let decoded = try JSONDecoder().decode([String: CivilDate].self, from: data)
        #expect(decoded["date"] == monday)
    }

    @Test func localDateDependsOnTimeZone() throws {
        // 03:30 UTC on March 3 is still March 2 in New York.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-03-03T03:30:00Z"))
        #expect(CivilDate(date: instant, timeZone: try #require(TimeZone(identifier: "America/New_York"))) == monday)
        #expect(CivilDate(date: instant, timeZone: try #require(TimeZone(identifier: "Europe/London"))) == monday.adding(days: 1))
    }
}

struct WakeTimeTests {
    @Test func wakeTimeIsLocalToTheWakeUpOffset() {
        let night = DemoData.night(wakingOn: monday, wakeMinute: 6 * 60 + 40, asleepMinutes: 420, utcOffsetSeconds: -5 * 3600)
        #expect(night.wakeMinuteOfDay == 400)
    }

    @Test func wakeTimeSurvivesTheDaylightSavingJump() {
        // Before and after the change, waking at 06:40 local reads as 06:40.
        let before = DemoData.night(wakingOn: CivilDate(year: 2026, month: 3, day: 7), wakeMinute: 400,
                                    asleepMinutes: 420, utcOffsetSeconds: -5 * 3600)
        let after = DemoData.night(wakingOn: CivilDate(year: 2026, month: 3, day: 9), wakeMinute: 400,
                                   asleepMinutes: 420, utcOffsetSeconds: -4 * 3600)
        #expect(before.wakeMinuteOfDay == 400)
        #expect(after.wakeMinuteOfDay == 400)
    }

    @Test func wakeTimeFollowsTimeZoneTravel() {
        // Flew New York → London: 07:00 in London is 07:00 locally, not 02:00.
        let london = DemoData.night(wakingOn: monday, wakeMinute: 7 * 60, asleepMinutes: 400, utcOffsetSeconds: 0)
        #expect(london.wakeMinuteOfDay == 420)
    }
}
