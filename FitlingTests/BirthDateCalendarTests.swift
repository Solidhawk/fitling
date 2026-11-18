import Foundation
import Testing
import FitlingCore
@testable import Fitling

@Suite(.serialized) struct BirthDateCalendarTests {
    @Test(arguments: ["America/Los_Angeles", "Pacific/Auckland", "Europe/Amsterdam"])
    func stableAcrossTimeZones(identifier: String) throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = try #require(TimeZone(identifier: identifier))

        let born = try #require(BirthDateCalendar.date(from: "2000-03-15"))
        #expect(BirthDateCalendar.string(from: born) == "2000-03-15")

        let birthday = try #require(BirthDateCalendar.date(from: "2026-03-15"))
        #expect(age(birthDate: born, on: birthday, calendar: BirthDateCalendar.calendar) == 26)
    }

    @Test func rejectsInvalidStrings() {
        #expect(BirthDateCalendar.date(from: "2000-02-30") == nil)
        #expect(BirthDateCalendar.date(from: "15-03-2000") == nil)
        #expect(BirthDateCalendar.date(from: "2000-3-15") == nil)
    }

    @Test func calendarIsGregorianUTC() {
        #expect(BirthDateCalendar.calendar.identifier == .gregorian)
        #expect(BirthDateCalendar.calendar.timeZone.secondsFromGMT() == 0)
    }
}
