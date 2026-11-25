import Foundation
import Testing
@testable import FitlingCore

/// The partner's reminders, shared by the app (local notifications) and the web (Web Push, phase 7). The same cases as
/// ReminderTests in the app, which keeps the ones about permission and the settings on the device.
@Suite struct ReminderPlannerTests {
    /// 11:06 UTC, as PartnerFixture in the app.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    var today: Day { Day(now, timeZone: .gmt) }

    func plan(_ settings: ReminderSettings) -> [PlannedReminder] {
        ReminderPlanner.plan(settings, tone: .sweet, now: now, timeZone: .gmt) { _ in .hungry }
    }

    @Test func schedulesAtMostTwoPerDay() {
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60, 18 * 60]))
        let perDay = Dictionary(grouping: reminders, by: \.day)
        #expect(perDay.keys.contains(today.adding(1)))
        #expect(perDay.values.allSatisfy { $0.count <= ReminderSettings.maximumPerDay })
        #expect(perDay[today.adding(1)]?.map(\.minutes) == [9 * 60, 12 * 60])
    }

    @Test func neverSchedulesAtNight() {
        let reminders = plan(ReminderSettings(isOn: true, times: [22 * 60 + 30, 7 * 60, 21 * 60]))
        #expect(reminders.isEmpty)
        let mixed = plan(ReminderSettings(isOn: true, times: [23 * 60, 13 * 60]))
        #expect(mixed.map(\.minutes).allSatisfy { $0 >= 8 * 60 && $0 < 21 * 60 })
        #expect(!mixed.isEmpty)
    }

    @Test func timesThatHavePassedTodayAreSkipped() {
        // 11:06 UTC: the 09:00 reminder of today is gone, the 12:30 one is still to come.
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60 + 30]))
        #expect(reminders.filter { $0.day == today }.map(\.minutes) == [12 * 60 + 30])
        #expect(reminders.filter { $0.day == today.adding(1) }.count == 2)
    }

    @Test func remindersOfOneDayReadDifferently() {
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60]))
        let tomorrow = reminders.filter { $0.day == today.adding(1) }.map(\.messageKey)
        #expect(Set(tomorrow).count == 2)
        #expect(tomorrow.allSatisfy { $0.hasPrefix("creature.message.hungry.sweet.") })
    }

    @Test func nothingIsScheduledWhenTurnedOff() {
        #expect(plan(ReminderSettings(isOn: false)).isEmpty)
    }

    @Test func eachDaySaysWhatThePartnerWouldSayThatDay() {
        let reminders = ReminderPlanner.plan(ReminderSettings(isOn: true), tone: .coach, now: now, timeZone: .gmt) { day in
            day == today ? .tooMuch : .fit
        }
        #expect(reminders.map(\.day) == [today, today, today.adding(1), today.adding(1)])
        #expect(reminders.filter { $0.day == today }.allSatisfy { $0.messageKey.hasPrefix("creature.message.tooMuch.coach.") })
        #expect(reminders.filter { $0.day == today.adding(1) }.allSatisfy { $0.messageKey.hasPrefix("creature.message.fit.coach.") })
    }

    /// The web has no time zones in the rules: it passes the day and the minutes where the user is, and gets the same.
    @Test func theDayAndMinutesGiveTheSamePlan() {
        let settings = ReminderSettings(isOn: true, times: [9 * 60, 12 * 60 + 30])
        let amsterdam = TimeZone(secondsFromGMT: 3600)!
        let byClock = ReminderPlanner.plan(settings, tone: .sweet, now: now, timeZone: amsterdam) { _ in .normal }
        let byDay = ReminderPlanner.plan(
            settings, tone: .sweet, today: Day(now, timeZone: amsterdam), minutesNow: ReminderPlanner.minutes(of: now, in: amsterdam)
        ) { _ in .normal }
        #expect(byClock == byDay)
        #expect(ReminderPlanner.minutes(of: now, in: amsterdam) == 12 * 60 + 6)
        #expect(byDay.first?.identifier == "fitling.reminder.\(today.isoString).1")
    }
}
