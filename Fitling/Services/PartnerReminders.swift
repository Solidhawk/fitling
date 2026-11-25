import Foundation
import UserNotifications
import FitlingCore

// ReminderSettings, PlannedReminder and ReminderPlanner live in FitlingCore, shared with the web (phase 7).

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
