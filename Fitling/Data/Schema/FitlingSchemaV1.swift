import Foundation
import SwiftData
import FitlingCore

enum FitlingSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [UserProfile.self] }

    @Model
    final class UserProfile {
        /// The Supabase auth user id.
        @Attribute(.unique) var id: UUID
        var healthConsentAt: Date
        var healthConsentVersion: Int
        /// Midnight UTC, see `BirthDateCalendar`.
        var birthDate: Date
        // Enums are stored as raw strings so `#Predicate` queries keep working.
        var sexRaw: String
        var heightCm: Double
        var weightKg: Double
        var activityLevelRaw: String
        var goalRaw: String
        var kcalTarget: Int
        var proteinTargetG: Int
        var carbsTargetG: Int
        var fatTargetG: Int
        var targetsAreManual: Bool
        var updatedAt: Date
        var needsPush: Bool

        init(
            id: UUID,
            healthConsentAt: Date,
            healthConsentVersion: Int,
            body: BodyProfile,
            targets: NutritionTargets,
            targetsAreManual: Bool,
            updatedAt: Date
        ) {
            self.id = id
            self.healthConsentAt = healthConsentAt
            self.healthConsentVersion = healthConsentVersion
            self.birthDate = body.birthDate
            self.sexRaw = body.sex.rawValue
            self.heightCm = body.heightCm
            self.weightKg = body.weightKg
            self.activityLevelRaw = body.activityLevel.rawValue
            self.goalRaw = body.goal.rawValue
            self.kcalTarget = targets.kcal
            self.proteinTargetG = targets.proteinG
            self.carbsTargetG = targets.carbsG
            self.fatTargetG = targets.fatG
            self.targetsAreManual = targetsAreManual
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }
}

typealias UserProfile = FitlingSchemaV1.UserProfile

extension UserProfile {
    var bodyProfile: BodyProfile {
        get {
            BodyProfile(
                birthDate: birthDate,
                sex: Sex(rawValue: sexRaw) ?? .other,
                heightCm: heightCm,
                weightKg: weightKg,
                activityLevel: ActivityLevel(rawValue: activityLevelRaw) ?? .sedentary,
                goal: Goal(rawValue: goalRaw) ?? .maintain
            )
        }
        set {
            birthDate = newValue.birthDate
            sexRaw = newValue.sex.rawValue
            heightCm = newValue.heightCm
            weightKg = newValue.weightKg
            activityLevelRaw = newValue.activityLevel.rawValue
            goalRaw = newValue.goal.rawValue
        }
    }

    var targets: NutritionTargets {
        get { NutritionTargets(kcal: kcalTarget, proteinG: proteinTargetG, carbsG: carbsTargetG, fatG: fatTargetG) }
        set {
            kcalTarget = newValue.kcal
            proteinTargetG = newValue.proteinG
            carbsTargetG = newValue.carbsG
            fatTargetG = newValue.fatG
        }
    }
}

func makeModelContainer(inMemory: Bool) throws -> ModelContainer {
    try ModelContainer(
        for: Schema(versionedSchema: FitlingSchemaV1.self),
        migrationPlan: FitlingMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
    )
}
