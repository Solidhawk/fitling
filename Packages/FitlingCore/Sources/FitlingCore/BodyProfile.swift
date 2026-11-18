import Foundation

// Raw values are the exact `check` values of the `profiles` table in Supabase.
public enum Sex: String, Sendable, CaseIterable, Codable {
    case male, female, other
}

public enum ActivityLevel: String, Sendable, CaseIterable, Codable {
    case sedentary, light, moderate, active
    case veryActive = "very_active"

    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

public enum Goal: String, Sendable, CaseIterable, Codable {
    case lose
    case buildMuscle = "build_muscle"
    case maintain, recomp

    public var kcalFactor: Double {
        switch self {
        case .lose: 0.80
        case .buildMuscle: 1.10
        case .maintain: 1.00
        case .recomp: 0.95
        }
    }

    public var proteinPerKg: Double {
        switch self {
        case .lose: 2.0
        case .buildMuscle: 1.8
        case .maintain: 1.6
        case .recomp: 2.2
        }
    }
}

public struct BodyProfile: Sendable, Equatable {
    public var birthDay: Day
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double
    public var activityLevel: ActivityLevel
    public var goal: Goal

    public init(birthDay: Day, sex: Sex, heightCm: Double, weightKg: Double, activityLevel: ActivityLevel, goal: Goal) {
        self.birthDay = birthDay
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.goal = goal
    }
}
