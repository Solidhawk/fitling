#if DEBUG
import Foundation
import FitlingCore

/// Keeps the reminders in memory instead of handing them to the system, and answers the
/// permission question without a system alert.
@MainActor
final class FakeReminderDelivery: ReminderDelivery {
    var grantsPermission = true
    private(set) var permissionRequests = 0
    private(set) var reminders: [PlannedReminder] = []
    private(set) var title = ""

    func requestPermission() async -> Bool {
        permissionRequests += 1
        return grantsPermission
    }

    func replace(with reminders: [PlannedReminder], title: String) {
        self.reminders = reminders
        self.title = title
    }
}
#endif
