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

    private static let kcalPerGramProtein = 4.0
    private static let kcalPerGramCarbs = 4.0
    private static let kcalPerGramFat = 9.0

    /// Mifflin-St Jeor, with the average of the male and female constants for `.other`.
    public static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78
        }
    }

    /// What part of the kcal target each macro brings: protein and carbs at 4 kcal per gram, fat at 9.
    public static func kcalShares(of targets: NutritionTargets) -> (protein: Double, carbs: Double, fat: Double) {
        guard targets.kcal > 0 else { return (0, 0, 0) }
        let kcal = Double(targets.kcal)
        return (
            Double(targets.proteinG) * kcalPerGramProtein / kcal,
            Double(targets.carbsG) * kcalPerGramCarbs / kcal,
            Double(targets.fatG) * kcalPerGramFat / kcal
        )
    }

    public static func commonMinimumKcal(for sex: Sex) -> Int {
        sex == .male ? 1500 : 1200
    }

    /// BMR, TDEE and the proposed targets for a profile.
    public static func plan(for profile: BodyProfile, on day: Day) -> EnergyPlan {
        let basal = bmr(
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            age: age(bornOn: profile.birthDay, on: day),
            sex: profile.sex
        )
        let tdee = basal * profile.activityLevel.multiplier
        let goalKcal = Int((tdee * profile.goal.kcalFactor / 10).rounded()) * 10
        // Rounded up: rounding to the nearest ten could end just under the floor.
        let floorKcal = Int((basal * floorFactor / 10).rounded(.up)) * 10
        let kcal = max(goalKcal, floorKcal, Limits.kcal.lowerBound)
        return EnergyPlan(
            bmr: basal,
            tdee: tdee,
            targets: macros(kcal: kcal, weightKg: profile.weightKg, goal: profile.goal),
            floorApplied: goalKcal < floorKcal,
            warnings: warnings(forKcal: kcal, bmr: basal, tdee: tdee, sex: profile.sex)
        )
    }

    /// Protein from body weight, fat as a fixed share, carbohydrates as the rest.
    public static func macros(kcal: Int, weightKg: Double, goal: Goal) -> NutritionTargets {
        let protein = Int((weightKg * goal.proteinPerKg).rounded())
        let fat = Int((Double(kcal) * fatShareOfKcal / kcalPerGramFat).rounded())
        let remainingKcal = Double(kcal) - Double(protein) * kcalPerGramProtein - Double(fat) * kcalPerGramFat
        let carbs = max(0, Int((remainingKcal / kcalPerGramCarbs).rounded()))
        return NutritionTargets(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    /// Warnings for a target the user typed in.
    public static func warnings(forKcal kcal: Int, bmr: Double, tdee: Double, sex: Sex) -> Set<TargetWarning> {
        var warnings: Set<TargetWarning> = []
        if Double(kcal) < bmr * floorFactor { warnings.insert(.belowFloor) }
        if kcal < commonMinimumKcal(for: sex) { warnings.insert(.belowCommonMinimum) }
        if Double(kcal) < tdee * (1 - largestDeficitShare) { warnings.insert(.largeDeficit) }
        return warnings
    }

    /// The targets for one day. With `countsWorkouts`, part of the workout energy from HealthKit
    /// is added as carbohydrates; protein and fat stay the same.
    public static func dayTargets(base: NutritionTargets, workoutKcal: Double, countsWorkouts: Bool) -> NutritionTargets {
        guard countsWorkouts, workoutKcal.isFinite, workoutKcal > 0 else { return base }
        let extraKcal = Int((workoutKcal * workoutEnergyShare).rounded())
        var targets = base
        targets.kcal = min(base.kcal + extraKcal, Limits.kcal.upperBound)
        targets.carbsG = min(base.carbsG + Int((Double(targets.kcal - base.kcal) / kcalPerGramCarbs).rounded()), Limits.carbsG.upperBound)
        return targets
    }
}
