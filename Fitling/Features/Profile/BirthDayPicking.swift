import Foundation
import FitlingCore

/// A birthday is a `Day`. The date pickers show it as midnight UTC on a Gregorian calendar in
/// UTC, so the picker shows the stored day whatever time zone the device is in.
enum BirthDayPicking {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func date(for day: Day) -> Date {
        let parts = day.components
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? .distantPast
    }

    static func day(for date: Date) -> Day {
        Day(date, timeZone: .gmt)
    }

    /// The same day of the month `years` years earlier; 29 February becomes 28 February.
    static func day(_ years: Int, yearsBefore day: Day) -> Day {
        let parts = day.components
        return Day(year: parts.year - years, month: parts.month, day: parts.day)
            ?? Day(year: parts.year - years, month: parts.month, day: parts.day - 1)
            ?? day
    }
}
