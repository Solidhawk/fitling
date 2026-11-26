#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The partner's reminders for the web (phase 7): what ReminderPlanner plans on the iPhone, for today and tomorrow, each
// with what the partner would say on that day. The browser knows the time zone; the rules get the day and the minutes.

struct RemindersRequest: Decodable {
    let settings: ReminderSettings
    /// Minutes after midnight where the user is.
    let minutesNow: Int
    /// The partner's days, as for partnerSnapshot; `today` is the user's day.
    let days: PartnerDaysRequest
}

struct ReminderOutput: Encodable {
    let identifier: String
    let day: String
    let minutes: Int
    let messageKey: String
}

struct RemindersAnswer: Encodable {
    let reminders: [ReminderOutput]
}

struct ReminderRules: Encodable {
    /// Minutes after midnight: no reminders from `quietFrom` until `quietUntil`.
    let quietFrom: Int
    let quietUntil: Int
    let maximumPerDay: Int
}

/// The quiet hours, for the time pickers on the partner tab (ReminderTime.allowedRange on iOS).
func reminderRules() -> ReminderRules {
    ReminderRules(
        quietFrom: ReminderSettings.quietFrom, quietUntil: ReminderSettings.quietUntil, maximumPerDay: ReminderSettings.maximumPerDay
    )
}

/// The reminders as PartnerViewModel plans them: the topic of each day from its snapshot (CreatureHistory.snapshot).
func remindersPlan(_ request: RemindersRequest) throws -> RemindersAnswer {
    let today = try day(request.days.today, "today")
    let historyDays = CreatureEngine.windowDays + 1
    var topics: [Day: MessageTopic] = [:]
    for offset in 0..<ReminderPlanner.daysAhead {
        let day = today.adding(offset)
        let records = try request.days.records(from: day.adding(-historyDays), through: day)
        topics[day] = CreatureEngine.topic(for: CreatureEngine.snapshot(of: request.days.creature, records: records, today: day))
    }
    let planned = ReminderPlanner.plan(
        request.settings, tone: request.days.creature.tone, today: today, minutesNow: request.minutesNow
    ) { topics[$0] ?? .hungry }
    return RemindersAnswer(reminders: planned.map {
        ReminderOutput(identifier: $0.identifier, day: $0.day.isoString, minutes: $0.minutes, messageKey: $0.messageKey)
    })
}
