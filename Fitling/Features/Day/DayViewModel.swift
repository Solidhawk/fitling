import Foundation
import Observation
import SwiftData
import FitlingCore

/// One day: what was eaten per meal, the totals against the target that applied that day, and
/// water. Recomputed from the store on every `reload()`, so a sync that brings in entries from
/// another device shows up as soon as the view reloads.
@Observable
@MainActor
final class DayViewModel {
    /// Water is added in glasses of this size.
    static let glassMl = 250

    private(set) var day: Day
    private(set) var entriesByMeal: [MealSlot: [FoodEntry]] = [:]
    private(set) var totals = DayTotals()
    private(set) var targets: NutritionTargets
    private(set) var waterMl = 0

    private let diary: FoodDiary
    private let profile: UserProfile
    private let timeZone: TimeZone

    init(profile: UserProfile, context: ModelContext, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.timeZone = timeZone
        diary = FoodDiary(context: context, userID: profile.id, now: now)
        day = Day(now(), timeZone: timeZone)
        targets = profile.targets
        reload()
    }

    var today: Day {
        Day(diary.now(), timeZone: timeZone)
    }

    var isToday: Bool {
        day == today
    }

    var userID: UUID {
        profile.id
    }

    var context: ModelContext {
        diary.context
    }

    func show(_ newDay: Day) {
        // The future has nothing to log yet.
        day = min(newDay, today)
        followsToday = day == today
        reload()
    }

    /// Looking at today: the screen moves on with the date, so what is logged the next morning lands on that day. A day
    /// the user went back to stays.
    private var followsToday = true

    /// The date moved on: at midnight, or when the app comes back on a later day. True when the screen moved with it.
    @discardableResult
    func dateChanged() -> Bool {
        guard followsToday, day != today else { return false }
        day = today
        reload()
        return true
    }

    func reload() {
        let entries = diary.entries(on: day)
        entriesByMeal = Dictionary(grouping: entries) { MealSlot(rawValue: $0.meal) ?? .snack }
        totals = FoodMath.totals(entries.map { Nutrients(kcal: $0.kcal, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG) })
        targets = diary.context.targets(on: day, for: profile)
        waterMl = diary.waterMl(on: day)
    }

    func addGlass() {
        diary.addWater(Self.glassMl, on: day)
        reload()
    }

    func delete(_ entry: FoodEntry) {
        diary.delete(entry)
        reload()
    }

    func kcal(of meal: MealSlot) -> Double {
        (entriesByMeal[meal] ?? []).reduce(0) { $0 + $1.kcal }
    }
}
