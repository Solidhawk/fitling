import Foundation

/// The `public.profiles` row as Supabase sends and receives it.
struct ProfileRecord: Codable, Equatable, Sendable {
    var id: UUID
    var healthConsentAt: Date
    var healthConsentVersion: Int
    /// `yyyy-MM-dd`, see `BirthDateCalendar`.
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
    var updatedAt: Date
    /// Set by the server; never sent.
    var syncedAt: Date?

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
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(_ profile: UserProfile) {
        id = profile.id
        healthConsentAt = profile.healthConsentAt
        healthConsentVersion = profile.healthConsentVersion
        birthDate = BirthDateCalendar.string(from: profile.birthDate)
        sex = profile.sexRaw
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        activityLevel = profile.activityLevelRaw
        goal = profile.goalRaw
        kcalTarget = profile.kcalTarget
        proteinTargetG = profile.proteinTargetG
        carbsTargetG = profile.carbsTargetG
        fatTargetG = profile.fatTargetG
        targetsAreManual = profile.targetsAreManual
        updatedAt = profile.updatedAt
        syncedAt = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(healthConsentAt, forKey: .healthConsentAt)
        try container.encode(healthConsentVersion, forKey: .healthConsentVersion)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(sex, forKey: .sex)
        try container.encode(heightCm, forKey: .heightCm)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(activityLevel, forKey: .activityLevel)
        try container.encode(goal, forKey: .goal)
        try container.encode(kcalTarget, forKey: .kcalTarget)
        try container.encode(proteinTargetG, forKey: .proteinTargetG)
        try container.encode(carbsTargetG, forKey: .carbsTargetG)
        try container.encode(fatTargetG, forKey: .fatTargetG)
        try container.encode(targetsAreManual, forKey: .targetsAreManual)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// Copies the server row into the local profile; the local copy is then in sync.
    func apply(to profile: UserProfile) {
        profile.healthConsentAt = healthConsentAt
        profile.healthConsentVersion = healthConsentVersion
        if let date = BirthDateCalendar.date(from: birthDate) { profile.birthDate = date }
        profile.sexRaw = sex
        profile.heightCm = heightCm
        profile.weightKg = weightKg
        profile.activityLevelRaw = activityLevel
        profile.goalRaw = goal
        profile.kcalTarget = kcalTarget
        profile.proteinTargetG = proteinTargetG
        profile.carbsTargetG = carbsTargetG
        profile.fatTargetG = fatTargetG
        profile.targetsAreManual = targetsAreManual
        profile.updatedAt = updatedAt
        profile.needsPush = false
    }
}
