import Foundation
import SwiftData
import FitlingCore

/// Turns the logs on this device into the days `CreatureEngine` judges, and keeps the stored
/// partner up to date with them.
@MainActor
struct CreatureHistory {
    let context: ModelContext
    let profile: UserProfile
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init

    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    /// One record per day with food logged or a workout done, from `start` through `end`. A day
    /// is compared with the target that applied on that day.
    func records(from start: Day, through end: Day) -> [DayRecord] {
        let userID = profile.id
        let first = start.isoString
        let last = end.isoString
        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.userID == userID && $0.deletedAt == nil && $0.consumedOn >= first && $0.consumedOn <= last }
        ))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> {
                $0.userID == userID && $0.deletedAt == nil && $0.endedAt != nil && $0.performedOn >= first && $0.performedOn <= last
            }
        ))) ?? []
        let activities = (try? context.fetch(FetchDescriptor<DayActivity>(
            predicate: #Predicate<DayActivity> { $0.day >= first && $0.day <= last && $0.workoutKcal > 0 }
        ))) ?? []

        let workoutDays = Set(sessions.map(\.performedOn)).union(activities.map(\.day))
        // The same rule as on the web (FitlingCore.DayRecords).
        return DayRecords.build(
            entries: entries.compactMap { entry in
                Day(isoString: entry.consumedOn).map { LoggedEntry(day: $0, kcal: entry.kcal, proteinG: entry.proteinG) }
            },
            workoutDays: Set(workoutDays.compactMap(Day.init(isoString:))),
            targets: { context.targets(on: $0, for: profile) }
        )
    }

    /// Folds every finished day into the partner's shape and XP, and saves only when that changed
    /// something. Returns what happened, for the partner screen to show once.
    @discardableResult
    func update(_ creature: Creature) -> [CreatureEvent] {
        guard let state = creature.state else { return [] }
        let start = CreatureEngine.firstRecordDay(toAdvance: state)
        let update = CreatureEngine.advance(state, records: records(from: start, through: today), today: today)
        guard update.state != state else { return update.events }
        creature.apply(update.state, at: now())
        try? context.save()
        return update.events
    }

    /// The partner right now, from the days that decide its mood: the last week and today.
    func snapshot(of creature: Creature, on day: Day? = nil) -> CreatureSnapshot? {
        guard let state = creature.state else { return nil }
        let target = day ?? today
        let records = self.records(from: target.adding(-(CreatureEngine.windowDays + 1)), through: target)
        return CreatureEngine.snapshot(of: state, records: records, today: target)
    }

    /// Today's record, for the XP the partner has earned so far today.
    func todayRecord() -> DayRecord? {
        records(from: today, through: today).first
    }
}
