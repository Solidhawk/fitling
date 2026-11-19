import Foundation
import SwiftData
import FitlingCore

extension FitlingSchemaV1 {
    @Model
    final class UserProfile {
        /// The Supabase auth user id.
        @Attribute(.unique) var id: UUID
        var healthConsentAt: Date
        var healthConsentVersion: Int
        var birthDate: String
        var sex: String
        var heightCm: Double
        var weightKg: Double
        var activityLevel: String
        var goal: String
        var kcalTarget: Int
        var proteinTargetG: Int
        var carbsTargetG: Int
        var fatTargetG: Int
        var targetsAreManual: Bool
        var countsWorkoutEnergy: Bool
        var postalCode: String?
        var updatedAt: Date
        var needsPush: Bool

        init(
            id: UUID, healthConsentAt: Date, healthConsentVersion: Int, body: BodyProfile,
            targets: NutritionTargets, targetsAreManual: Bool, updatedAt: Date
        ) {
            self.id = id
            self.healthConsentAt = healthConsentAt
            self.healthConsentVersion = healthConsentVersion
            self.birthDate = body.birthDay.isoString
            self.sex = body.sex.rawValue
            self.heightCm = body.heightCm
            self.weightKg = body.weightKg
            self.activityLevel = body.activityLevel.rawValue
            self.goal = body.goal.rawValue
            self.kcalTarget = targets.kcal
            self.proteinTargetG = targets.proteinG
            self.carbsTargetG = targets.carbsG
            self.fatTargetG = targets.fatG
            self.targetsAreManual = targetsAreManual
            self.countsWorkoutEnergy = false
            self.postalCode = nil
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    /// The targets from `effectiveOn` until the next period starts. Two rows for the same day can
    /// exist after two devices changed the targets offline; the one with the latest `updatedAt` counts.
    @Model
    final class TargetPeriod {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var effectiveOn: String
        var kcalTarget: Int
        var proteinTargetG: Int
        var carbsTargetG: Int
        var fatTargetG: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, effectiveOn: Day, targets: NutritionTargets, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.effectiveOn = effectiveOn.isoString
            self.kcalTarget = targets.kcal
            self.proteinTargetG = targets.proteinG
            self.carbsTargetG = targets.carbsG
            self.fatTargetG = targets.fatG
            self.updatedAt = updatedAt
            self.deletedAt = nil
            self.needsPush = true
        }
    }
}

extension UserProfile {
    /// Nil when the stored values are not ones this app version knows, which can only happen
    /// after a newer version wrote them.
    var bodyProfile: BodyProfile? {
        guard let birthDay = Day(isoString: birthDate), let sex = Sex(rawValue: sex),
              let activityLevel = ActivityLevel(rawValue: activityLevel), let goal = Goal(rawValue: goal) else { return nil }
        return BodyProfile(
            birthDay: birthDay, sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel, goal: goal
        )
    }

    var targets: NutritionTargets {
        NutritionTargets(kcal: kcalTarget, proteinG: proteinTargetG, carbsG: carbsTargetG, fatG: fatTargetG)
    }
}

extension TargetPeriod {
    var targets: NutritionTargets {
        NutritionTargets(kcal: kcalTarget, proteinG: proteinTargetG, carbsG: carbsTargetG, fatG: fatTargetG)
    }
}

extension UserProfile {
    /// Takes over a profile the user entered. The caller marks the change (`updatedAt`, `needsPush`).
    func update(body: BodyProfile) {
        birthDate = body.birthDay.isoString
        sex = body.sex.rawValue
        heightCm = body.heightCm
        weightKg = body.weightKg
        activityLevel = body.activityLevel.rawValue
        goal = body.goal.rawValue
    }

    func update(targets: NutritionTargets) {
        kcalTarget = targets.kcal
        proteinTargetG = targets.proteinG
        carbsTargetG = targets.carbsG
        fatTargetG = targets.fatG
    }
}
