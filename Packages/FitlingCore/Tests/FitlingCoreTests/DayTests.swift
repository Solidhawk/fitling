import Foundation
import Testing
@testable import FitlingCore

func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Day {
    Day(year: year, month: month, day: dayOfMonth)!
}

@Suite struct DayTests {
    @Test func countsDaysSinceTheStartOf1970() {
        #expect(day(1970, 1, 1).ordinal == 0)
        #expect(day(1969, 12, 31).ordinal == -1)
        #expect(day(2026, 11, 18).ordinal == 20775)
    }

    @Test func givesBackTheDateItWasMadeFrom() {
        let components = day(2024, 2, 29).components
        #expect(components.year == 2024)
        #expect(components.month == 2)
        #expect(components.day == 29)
    }

    @Test func rejectsDatesThatDoNotExist() {
        #expect(Day(year: 2026, month: 2, day: 30) == nil)
        #expect(Day(year: 2025, month: 2, day: 29) == nil)
        #expect(Day(year: 2026, month: 13, day: 1) == nil)
        #expect(Day(year: 2026, month: 4, day: 0) == nil)
    }

    @Test func writesAndReadsThePostgresDateFormat() {
        #expect(day(2026, 3, 5).isoString == "2026-03-05")
        #expect(Day(isoString: "2026-03-05") == day(2026, 3, 5))
        #expect(Day(isoString: "2026-3-5") == nil)
        #expect(Day(isoString: "05-03-2026") == nil)
        #expect(Day(isoString: "2026-02-30") == nil)
        #expect(Day(isoString: "") == nil)
    }

    @Test func addingDaysCrossesMonthsAndYears() {
        #expect(day(2026, 12, 31).adding(1) == day(2027, 1, 1))
        #expect(day(2026, 3, 1).adding(-1) == day(2026, 2, 28))
    }

    @Test func weekStartsOnMonday() {
        #expect(day(2026, 11, 18).weekStart == day(2026, 11, 16))
        #expect(day(2026, 11, 16).weekStart == day(2026, 11, 16))
        #expect(day(2026, 11, 22).weekStart == day(2026, 11, 16))
        #expect(day(1969, 12, 31).weekStart == day(1969, 12, 29))
    }

    @Test func lateEveningFallsOnTheNextDayFurtherEast() {
        // 2026-11-18 23:30 UTC
        let moment = Date(timeIntervalSince1970: 1_795_044_600)
        #expect(Day(moment, timeZone: TimeZone(secondsFromGMT: 0)!) == day(2026, 11, 18))
        #expect(Day(moment, timeZone: TimeZone(secondsFromGMT: 3600)!) == day(2026, 11, 19))
    }

    @Test func ordersByDate() {
        #expect(day(2026, 11, 17) < day(2026, 11, 18))
        #expect([day(2026, 11, 18), day(2025, 1, 1)].sorted() == [day(2025, 1, 1), day(2026, 11, 18)])
    }

    @Test func encodesAsAPlainDateString() throws {
        let data = try JSONEncoder().encode([day(2026, 11, 18)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-11-18\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [day(2026, 11, 18)])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Day].self, from: Data("[\"gisteren\"]".utf8))
        }
    }
}
