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
        reload()
    }

    func reload() {
        let entries = diary.entries(on: day)
        entriesByMeal = Dictionary(grouping: entries) { MealSlot(rawValue: $0.meal) ?? .snack }
        totals = FoodMath.totals(entries.map { Nutrients(kcal: $0.kcal, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG) })
        targets = targets(on: day)
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

    /// The target that applied on `day`: the latest period that started on or before it, the
    /// newest row when two devices made one for the same day. Workout energy is added when the
    /// user chose that (ARCHITECTURE §7).
    private func targets(on day: Day) -> NutritionTargets {
        let userID = profile.id
        let dayString = day.isoString
        var descriptor = FetchDescriptor<TargetPeriod>(
            predicate: #Predicate<TargetPeriod> { $0.userID == userID && $0.deletedAt == nil && $0.effectiveOn <= dayString },
            sortBy: [SortDescriptor(\.effectiveOn, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let base = (try? diary.context.fetch(descriptor).first)?.targets ?? profile.targets
        let workoutKcal = workoutKcal(on: day)
        return NutritionEngine.dayTargets(base: base, workoutKcal: workoutKcal, countsWorkouts: profile.countsWorkoutEnergy)
    }

    private func workoutKcal(on day: Day) -> Double {
        let dayString = day.isoString
        var descriptor = FetchDescriptor<DayActivity>(predicate: #Predicate<DayActivity> { $0.day == dayString })
        descriptor.fetchLimit = 1
        return (try? diary.context.fetch(descriptor).first)?.workoutKcal ?? 0
    }
}
