#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// When the partner may send a reminder. Kept on the device: on the iPhone reminders are local notifications, on the
/// web each browser has its own, and a second device may want other times.
public struct ReminderSettings: Codable, Equatable, Sendable {
    public static let maximumPerDay = 2
    /// No reminders from 21:00 until 08:00.
    public static let quietFrom = 21 * 60
    public static let quietUntil = 8 * 60

    public var isOn: Bool
    /// Minutes after midnight. Lunch and dinner by default.
    public var times: [Int]

    public init(isOn: Bool = false, times: [Int] = [12 * 60 + 30, 18 * 60 + 30]) {
        self.isOn = isOn
        self.times = times
    }

    public static func isAllowed(_ minutes: Int) -> Bool {
        minutes >= quietUntil && minutes < quietFrom
    }

    /// The times that are actually used: outside the quiet hours, at most two, in order.
    public var usableTimes: [Int] {
        Array(Set(times.filter(Self.isAllowed)).sorted().prefix(Self.maximumPerDay))
    }
}

/// One reminder at one moment, with the String Catalog key of its text.
public struct PlannedReminder: Equatable, Sendable {
    public let identifier: String
    public let day: Day
    /// Minutes after midnight on `day`.
    public let minutes: Int
    public let messageKey: String

    public init(identifier: String, day: Day, minutes: Int, messageKey: String) {
        self.identifier = identifier
        self.day = day
        self.minutes = minutes
        self.messageKey = messageKey
    }
}

/// Works out the reminders for today and tomorrow. Each says what the partner would say on that day: `topic` gives the
/// subject from the logs as they are now.
public enum ReminderPlanner {
    public static let daysAhead = 2

    public static func plan(
        _ settings: ReminderSettings, tone: MessageTone, now: Date, timeZone: TimeZone,
        topic: (Day) -> MessageTopic
    ) -> [PlannedReminder] {
        plan(settings, tone: tone, today: Day(now, timeZone: timeZone), minutesNow: minutes(of: now, in: timeZone), topic: topic)
    }

    /// The same plan from the day and the minutes after midnight where the user is, for a caller that keeps its own
    /// clock (the web: the browser knows the time zone, the rules do not).
    public static func plan(
        _ settings: ReminderSettings, tone: MessageTone, today: Day, minutesNow: Int,
        topic: (Day) -> MessageTopic
    ) -> [PlannedReminder] {
        guard settings.isOn else { return [] }
        var reminders: [PlannedReminder] = []
        for offset in 0..<daysAhead {
            let day = today.adding(offset)
            let keys = CreatureEngine.messageKeys(topic: topic(day), tone: tone)
            for (index, minutes) in settings.usableTimes.enumerated() where offset > 0 || minutes > minutesNow {
                // Two a day, three variants: the variant moves on with every reminder.
                let variant = ((day.ordinal * ReminderSettings.maximumPerDay + index) % keys.count + keys.count) % keys.count
                reminders.append(PlannedReminder(
                    identifier: "fitling.reminder.\(day.isoString).\(index)", day: day, minutes: minutes, messageKey: keys[variant]
                ))
            }
        }
        return reminders
    }

    /// Minutes after midnight in `timeZone`, counted as Day counts days.
    public static func minutes(of date: Date, in timeZone: TimeZone) -> Int {
        let localSeconds = Int((date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))).rounded(.down))
        return ((localSeconds % 86400) + 86400) % 86400 / 60
    }
}
