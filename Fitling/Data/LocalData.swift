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
