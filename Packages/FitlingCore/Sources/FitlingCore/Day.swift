import Foundation

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
        self.ordinal = 0
    }

    /// The day on which `date` falls in `timeZone`. Always Gregorian, whatever calendar the
    /// device uses, so the stored value means the same on every device.
    public init(_ date: Date, timeZone: TimeZone) {
        self.ordinal = 0
    }

    /// The format of a Postgres `date`: "2026-11-18".
    public init?(isoString: String) {
        self.ordinal = 0
    }

    public var components: (year: Int, month: Int, day: Int) {
        (1970, 1, 1)
    }

    public var isoString: String {
        ""
    }

    /// The Monday of this day's week. Training volume counts per Monday-to-Sunday week in every
    /// locale, so a week of training reads the same for everyone.
    public var weekStart: Day {
        self
    }

    public func adding(_ days: Int) -> Day {
        self
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        lhs.ordinal < rhs.ordinal
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
