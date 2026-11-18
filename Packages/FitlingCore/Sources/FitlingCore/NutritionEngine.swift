import Foundation

/// Energy and macro targets from fixed formulas. Nothing here is estimated or tuned per user.
public enum NutritionEngine {
    /// A proposed kcal target never goes under this share of the BMR.
    public static let floorFactor = 1.1
    /// A manual target more than this share under the total expenditure gets a warning.
    public static let largestDeficitShare = 0.25
    /// The share of workout energy that is added to the day's budget. Half, because the activity
    /// factor already covers part of the training and wearables tend to overestimate.
    public static let workoutEnergyShare = 0.5
    public static let fatShareOfKcal = 0.25

    /// Mifflin-St Jeor, with the average of the male and female constants for `.other`.
    public static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        0
    }

    public static func commonMinimumKcal(for sex: Sex) -> Int {
        0
    }

    /// BMR, TDEE and the proposed targets for a profile.
    public static func plan(for profile: BodyProfile, on date: Date, calendar: Calendar) -> EnergyPlan {
        EnergyPlan(bmr: 0, tdee: 0, targets: NutritionTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0), floorApplied: false, warnings: [])
    }

    /// Protein from body weight, fat as a fixed share, carbohydrates as the rest.
    public static func macros(kcal: Int, weightKg: Double, goal: Goal) -> NutritionTargets {
        NutritionTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    /// Warnings for a target the user typed in.
    public static func warnings(forKcal kcal: Int, bmr: Double, tdee: Double, sex: Sex) -> Set<TargetWarning> {
        []
    }

    /// The targets for one day. With `countsWorkouts`, part of the workout energy from HealthKit
    /// is added as carbohydrates; protein and fat stay the same.
    public static func dayTargets(base: NutritionTargets, workoutKcal: Double, countsWorkouts: Bool) -> NutritionTargets {
        NutritionTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }
}
