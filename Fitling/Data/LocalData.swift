import Foundation
import SwiftData
import FitlingCore

extension ModelContext {
    /// The profile of `userID` on this device, if there is one.
    func profile(of userID: UUID) -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate<UserProfile> { $0.id == userID })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// The partner of `userID` on this device, if there is one.
    func creature(of userID: UUID) -> Creature? {
        var descriptor = FetchDescriptor<Creature>(predicate: #Predicate<Creature> { $0.userID == userID })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// The target that applied on `day`: the latest period that started on or before it, the
    /// newest row when two devices made one for the same day. Workout energy is added when the
    /// user chose that (ARCHITECTURE §7).
    func targets(on day: Day, for profile: UserProfile) -> NutritionTargets {
        let userID = profile.id
        let dayString = day.isoString
        var descriptor = FetchDescriptor<TargetPeriod>(
            predicate: #Predicate<TargetPeriod> { $0.userID == userID && $0.deletedAt == nil && $0.effectiveOn <= dayString },
            sortBy: [SortDescriptor(\.effectiveOn, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let base = (try? fetch(descriptor).first)?.targets ?? profile.targets
        return NutritionEngine.dayTargets(base: base, workoutKcal: workoutKcal(on: day), countsWorkouts: profile.countsWorkoutEnergy)
    }

    /// Workout energy that Apple Health reported for `day`.
    func workoutKcal(on day: Day) -> Double {
        let dayString = day.isoString
        var descriptor = FetchDescriptor<DayActivity>(predicate: #Predicate<DayActivity> { $0.day == dayString })
        descriptor.fetchLimit = 1
        return (try? fetch(descriptor).first)?.workoutKcal ?? 0
    }

    /// Records `targets` as the targets from `day` on, so a day is always compared with the target
    /// that held then. A second change on the same day updates that day's period instead of
    /// adding one.
    @discardableResult
    func recordTargets(_ targets: NutritionTargets, for userID: UUID, from day: Day, at moment: Date) -> TargetPeriod {
        let effectiveOn = day.isoString
        let descriptor = FetchDescriptor<TargetPeriod>(
            predicate: #Predicate<TargetPeriod> { $0.userID == userID && $0.effectiveOn == effectiveOn && $0.deletedAt == nil }
        )
        if let period = (try? fetch(descriptor))?.max(by: { $0.updatedAt < $1.updatedAt }) {
            period.kcalTarget = targets.kcal
            period.proteinTargetG = targets.proteinG
            period.carbsTargetG = targets.carbsG
            period.fatTargetG = targets.fatG
            period.updatedAt = moment
            period.needsPush = true
            return period
        }
        let period = TargetPeriod(id: UUID(), userID: userID, effectiveOn: day, targets: targets, updatedAt: moment)
        insert(period)
        return period
    }
}
