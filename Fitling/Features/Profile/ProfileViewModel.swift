import Foundation
import Observation
import SwiftData
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
    private let sync: SyncEngine
    private let timeZone: TimeZone
    private let now: () -> Date
    private var syncTask: Task<Void, Never>?

    init(profile: UserProfile, sync: SyncEngine, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.sync = sync
        self.timeZone = timeZone
        self.now = now
    }

    /// Today where the user is.
    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    /// Nil only when a newer app version stored a value this version does not know.
    var plan: EnergyPlan? {
        profile.bodyProfile.map { NutritionEngine.plan(for: $0, on: today) }
    }

    var syncProblemKey: String? {
        sync.problemKey
    }

    /// Warnings for the target as it is now, also one the user typed in. They never block (D-10).
    var warnings: [TargetWarning] {
        guard let plan, let body = profile.bodyProfile else { return [] }
        let found = NutritionEngine.warnings(forKcal: profile.kcalTarget, bmr: plan.bmr, tdee: plan.tdee, sex: body.sex)
        return TargetWarning.allCases.filter(found.contains)
    }

    func saveProfile(_ body: BodyProfile) -> SaveResult {
        profile.update(body: body)
        if !profile.targetsAreManual, let plan {
            setTargets(plan.targets)
        }
        markChanged()
        return profile.targetsAreManual ? .askRecalculate : .saved
    }

    func recalculateTargets() {
        guard let plan else { return }
        setTargets(plan.targets)
        profile.targetsAreManual = false
        markChanged()
    }

    func saveTargets(_ targets: NutritionTargets) throws(TargetsError) {
        guard Limits.kcal.contains(targets.kcal) else { throw .outOfRange(field: "kcal") }
        guard Limits.proteinG.contains(targets.proteinG) else { throw .outOfRange(field: "protein") }
        guard Limits.carbsG.contains(targets.carbsG) else { throw .outOfRange(field: "carbs") }
        guard Limits.fatG.contains(targets.fatG) else { throw .outOfRange(field: "fat") }
        setTargets(targets)
        profile.targetsAreManual = true
        markChanged()
    }

    /// New targets hold from today on; earlier days keep the targets they had.
    private func setTargets(_ targets: NutritionTargets) {
        profile.update(targets: targets)
    }

    /// Saved right away, so a change survives the app being closed; sent a moment later.
    private func markChanged() {
        profile.updatedAt = now()
        profile.needsPush = true
        scheduleSync()
    }

    /// Waits two seconds so a burst of edits becomes one round (ARCHITECTURE §3.5).
    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [sync] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync.sync()
        }
    }
}
