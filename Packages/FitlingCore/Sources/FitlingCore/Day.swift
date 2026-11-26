#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A calendar day as the user lived it, without a time or time zone. Logs, the creature and the
/// week menu count in days; a `Date` would shift a late-evening meal to another day when the
/// user travels or the clock changes.
public struct Day: Hashable, Comparable, Sendable {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    public let ordinal: Int

    public init(ordinal: Int) {
        self.ordinal = ordinal
    }

    /// Nil when the date does not exist, such as 30 February.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let candidate = Day(ordinal: Self.ordinal(year: year, month: month, day: day))
        // A day past the end of the month lands in the next month; reading it back shows that.
        guard candidate.components == (year, month, day) else { return nil }
        self = candidate
    }

    /// The day on which `date` falls in `timeZone`. Always Gregorian, whatever calendar the
    /// device uses, so the stored value means the same on every device.
    public init(_ date: Date, timeZone: TimeZone) {
        let localSeconds = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        self.ordinal = Int((localSeconds / 86400).rounded(.down))
    }

    /// The format of a Postgres `date`: "2026-11-18".
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var components: (year: Int, month: Int, day: Int) {
        // Howard Hinnant's civil_from_days. Integer division must round down, also for
        // negative numbers, hence the explicit era adjustment.
        let shifted = ordinal + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    public var isoString: String {
        let (year, month, day) = components
        return "\(Self.padded(year, to: 4))-\(Self.padded(month, to: 2))-\(Self.padded(day, to: 2))"
    }

    /// The Monday of this day's week. Training volume counts per Monday-to-Sunday week in every
    /// locale, so a week of training reads the same for everyone.
    public var weekStart: Day {
        // 1970-01-01 was a Thursday, three days after a Monday.
        let daysSinceMonday = ((ordinal + 3) % 7 + 7) % 7
        return adding(-daysSinceMonday)
    }

    public func adding(_ days: Int) -> Day {
        Day(ordinal: ordinal + days)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Howard Hinnant's days_from_civil.
    private static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear = month <= 2 ? year - 1 : year
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func padded(_ value: Int, to length: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, length - digits.count)) + digits
    }
}

extension Day: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(isoString: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a day: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
