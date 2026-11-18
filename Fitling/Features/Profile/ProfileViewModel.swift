import Foundation
import Observation
import FitlingCore

@Observable
@MainActor
final class ProfileViewModel {
    enum SaveResult: Equatable {
        case saved
        /// The targets were set by hand; the user decides whether the new profile replaces them.
        case askRecalculate
    }

    enum TargetsError: Error, Equatable {
        case outOfRange(field: String)
    }

    let profile: UserProfile
    private let sync: ProfileSync
    private let now: () -> Date
    private var pushTask: Task<Void, Never>?

    init(profile: UserProfile, sync: ProfileSync, now: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.sync = sync
        self.now = now
    }

    var calculation: EnergyCalculation {
        calculateEnergy(for: profile.bodyProfile, on: now(), calendar: BirthDateCalendar.calendar)
    }

    var isBelowSafeMinimum: Bool {
        profile.kcalTarget < safeMinimumKcal(for: profile.bodyProfile.sex)
    }

    func saveProfile(_ body: BodyProfile) -> SaveResult {
        profile.bodyProfile = body
        if !profile.targetsAreManual {
            profile.targets = calculation.targets
        }
        markChanged()
        return profile.targetsAreManual ? .askRecalculate : .saved
    }

    func recalculateTargets() {
        profile.targets = calculation.targets
        profile.targetsAreManual = false
        markChanged()
    }

    func saveTargets(_ targets: NutritionTargets) throws(TargetsError) {
        guard Limits.kcal.contains(targets.kcal) else { throw .outOfRange(field: "kcal") }
        guard Limits.proteinG.contains(targets.proteinG) else { throw .outOfRange(field: "protein") }
        guard Limits.carbsG.contains(targets.carbsG) else { throw .outOfRange(field: "carbs") }
        guard Limits.fatG.contains(targets.fatG) else { throw .outOfRange(field: "fat") }
        profile.targets = targets
        profile.targetsAreManual = true
        markChanged()
    }

    private func markChanged() {
        profile.updatedAt = now()
        profile.needsPush = true
        schedulePush()
    }

    /// Waits two seconds so a burst of edits becomes one request.
    private func schedulePush() {
        pushTask?.cancel()
        let userID = profile.id
        pushTask = Task { [sync] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await sync.push(userID: userID)
        }
    }
}
