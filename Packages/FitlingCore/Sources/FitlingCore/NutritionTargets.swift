#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

public struct NutritionTargets: Sendable, Equatable, Codable {
    public var kcal: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int

    public init(kcal: Int, proteinG: Int, carbsG: Int, fatG: Int) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// Why a kcal target deserves a second look. The app warns; it never blocks a manual choice.
public enum TargetWarning: String, Sendable, CaseIterable, Codable {
    /// Under `NutritionEngine.floorFactor` × BMR.
    case belowFloor = "below_floor"
    /// Under what is commonly given as the lowest advisable intake (1500 kcal for men, 1200 otherwise).
    case belowCommonMinimum = "below_common_minimum"
    /// More than `NutritionEngine.largestDeficitShare` under the total expenditure.
    case largeDeficit = "large_deficit"
}

/// The outcome of the target calculation, with the intermediate numbers so the app can explain it.
public struct EnergyPlan: Sendable, Equatable {
    public let bmr: Double
    public let tdee: Double
    public let targets: NutritionTargets
    /// True when the goal factor would have gone under the floor and the floor was used instead.
    public let floorApplied: Bool
    public let warnings: Set<TargetWarning>

    public init(bmr: Double, tdee: Double, targets: NutritionTargets, floorApplied: Bool, warnings: Set<TargetWarning>) {
        self.bmr = bmr
        self.tdee = tdee
        self.targets = targets
        self.floorApplied = floorApplied
        self.warnings = warnings
    }
}
