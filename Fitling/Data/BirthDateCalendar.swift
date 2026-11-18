import Foundation

/// One fixed calendar for birth dates: the date picker, the age calculation and the `yyyy-MM-dd`
/// sent to Postgres all use it, so a birth date never shifts a day in time zones west of UTC.
enum BirthDateCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func string(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String) -> Date? {
        let fields = string.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        // Calendar rolls invalid days over (30 February becomes 2 March); reject those.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
