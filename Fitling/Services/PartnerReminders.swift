import Foundation
import UserNotifications
import FitlingCore

/// When the partner may send a reminder. Kept on the device: reminders are local notifications,
/// and a second phone may want other times.
struct ReminderSettings: Codable, Equatable {
    static let maximumPerDay = 2
    /// No reminders from 21:00 until 08:00.
    static let quietFrom = 21 * 60
    static let quietUntil = 8 * 60

    var isOn = false
    /// Minutes after midnight. Lunch and dinner by default.
    var times = [12 * 60 + 30, 18 * 60 + 30]

    static func isAllowed(_ minutes: Int) -> Bool {
        minutes >= quietUntil && minutes < quietFrom
    }

    /// The times that are actually used: outside the quiet hours, at most two, in order.
    var usableTimes: [Int] {
        Array(Set(times.filter(Self.isAllowed)).sorted().prefix(Self.maximumPerDay))
    }
}

/// One reminder at one moment, with the String Catalog key of its text.
struct PlannedReminder: Equatable {
    let identifier: String
    let day: Day
    /// Minutes after midnight on `day`.
    let minutes: Int
    let messageKey: String
}

/// Works out the reminders for today and tomorrow. Each says what the partner would say on that
/// day: `topic` gives the subject from the logs as they are now.
enum ReminderPlanner {
    static let daysAhead = 2

    static func plan(
        _ settings: ReminderSettings, tone: MessageTone, now: Date, timeZone: TimeZone,
        topic: (Day) -> MessageTopic
    ) -> [PlannedReminder] {
        guard settings.isOn else { return [] }
        let today = Day(now, timeZone: timeZone)
        let minutesNow = minutes(of: now, in: timeZone)
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

    static func minutes(of date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Hands reminders to the system. A fake stands in for it in the tests and the UI test.
@MainActor
protocol ReminderDelivery: AnyObject {
    /// Asks once; afterwards the system answers without asking again.
    func requestPermission() async -> Bool
    /// Replaces every reminder that is waiting with `reminders`.
    func replace(with reminders: [PlannedReminder], title: String)
}

@MainActor
final class SystemReminderDelivery: ReminderDelivery {
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func replace(with reminders: [PlannedReminder], title: String) {
        let center = UNUserNotificationCenter.current()
        // The app sends no other local notifications, so everything waiting is a reminder.
        center.removeAllPendingNotificationRequests()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = Bundle.main.localizedString(forKey: reminder.messageKey, value: nil, table: nil)
            content.sound = .default
            let parts = reminder.day.components
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: reminder.minutes / 60, minute: reminder.minutes % 60),
                repeats: false
            )
            center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }
}

/// Where the settings are kept on this device.
struct ReminderSettingsStore {
    static let key = "fitling.partnerReminders"
    let defaults: UserDefaults

    func load() -> ReminderSettings {
        guard let data = defaults.data(forKey: Self.key), let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data) else {
            return ReminderSettings()
        }
        return settings
    }

    func save(_ settings: ReminderSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}
