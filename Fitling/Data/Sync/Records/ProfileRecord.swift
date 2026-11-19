import Foundation
import SwiftData
import FitlingCore

/// A row of `profiles`.
struct ProfileRecord: SyncRecord, Equatable {
    var id: UUID
    var healthConsentAt: Date
    var healthConsentVersion: Int
    var birthDate: Day
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
    var syncedAt: Date?

    /// A profile is never deleted on its own; it goes with the account.
    var deletedAt: Date? { nil }

    enum CodingKeys: String, CodingKey {
        case id
        case healthConsentAt = "health_consent_at"
        case healthConsentVersion = "health_consent_version"
        case birthDate = "birth_date"
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case activityLevel = "activity_level"
        case goal
        case kcalTarget = "kcal_target"
        case proteinTargetG = "protein_target_g"
        case carbsTargetG = "carbs_target_g"
        case fatTargetG = "fat_target_g"
        case targetsAreManual = "targets_are_manual"
        case countsWorkoutEnergy = "counts_workout_energy"
        case postalCode = "postal_code"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }
}

extension UserProfile: SyncableModel {
    static var tableName: String { "profiles" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<UserProfile> {
        FetchDescriptor(predicate: #Predicate<UserProfile> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<UserProfile> {
        FetchDescriptor(predicate: #Predicate<UserProfile> { ids.contains($0.id) })
    }

    static func make(from record: ProfileRecord) -> UserProfile {
        // The typed values only get the row started; `apply` then stores the server's own text,
        // including a value a newer app version may have written.
        let body = BodyProfile(
            birthDay: record.birthDate,
            sex: Sex(rawValue: record.sex) ?? .other,
            heightCm: record.heightCm,
            weightKg: record.weightKg,
            activityLevel: ActivityLevel(rawValue: record.activityLevel) ?? .sedentary,
            goal: Goal(rawValue: record.goal) ?? .maintain
        )
        let targets = NutritionTargets(
            kcal: record.kcalTarget, proteinG: record.proteinTargetG, carbsG: record.carbsTargetG, fatG: record.fatTargetG
        )
        let profile = UserProfile(
            id: record.id, healthConsentAt: record.healthConsentAt, healthConsentVersion: record.healthConsentVersion,
            body: body, targets: targets, targetsAreManual: record.targetsAreManual, updatedAt: record.updatedAt
        )
        profile.apply(record)
        return profile
    }

    var syncID: UUID { id }
    var deletedAt: Date? { nil }

    var record: ProfileRecord {
        ProfileRecord(
            id: id, healthConsentAt: healthConsentAt, healthConsentVersion: healthConsentVersion,
            birthDate: Day(isoString: birthDate) ?? Limits.earliestBirthDay, sex: sex, heightCm: heightCm, weightKg: weightKg,
            activityLevel: activityLevel, goal: goal, kcalTarget: kcalTarget, proteinTargetG: proteinTargetG,
            carbsTargetG: carbsTargetG, fatTargetG: fatTargetG, targetsAreManual: targetsAreManual,
            countsWorkoutEnergy: countsWorkoutEnergy, postalCode: postalCode, updatedAt: updatedAt, syncedAt: nil
        )
    }

    func apply(_ record: ProfileRecord) {
        healthConsentAt = record.healthConsentAt
        healthConsentVersion = record.healthConsentVersion
        birthDate = record.birthDate.isoString
        sex = record.sex
        heightCm = record.heightCm
        weightKg = record.weightKg
        activityLevel = record.activityLevel
        goal = record.goal
        kcalTarget = record.kcalTarget
        proteinTargetG = record.proteinTargetG
        carbsTargetG = record.carbsTargetG
        fatTargetG = record.fatTargetG
        targetsAreManual = record.targetsAreManual
        countsWorkoutEnergy = record.countsWorkoutEnergy
        postalCode = record.postalCode
        updatedAt = record.updatedAt
        needsPush = false
    }
}
