import Foundation

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

public struct EnergyCalculation: Sendable, Equatable {
    public let bmr: Double
    public let tdee: Double
    public let targets: NutritionTargets
    public let isBelowSafeMinimum: Bool
}
