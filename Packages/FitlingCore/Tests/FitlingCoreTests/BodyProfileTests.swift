import Foundation
import Testing
@testable import FitlingCore

@Suite struct BodyProfileTests {
    @Test func rawValuesMatchDatabase() {
        #expect(Sex.allCases.map(\.rawValue) == ["male", "female", "other"])
        #expect(ActivityLevel.allCases.map(\.rawValue) == ["sedentary", "light", "moderate", "active", "very_active"])
        #expect(Goal.allCases.map(\.rawValue) == ["lose", "build_muscle", "maintain", "recomp"])
    }

    @Test func activityMultipliers() {
        #expect(ActivityLevel.allCases.map(\.multiplier) == [1.2, 1.375, 1.55, 1.725, 1.9])
    }

    @Test func goalFactors() {
        #expect(Goal.allCases.map(\.kcalFactor) == [0.80, 1.10, 1.00, 0.95])
        #expect(Goal.allCases.map(\.proteinPerKg) == [2.0, 1.8, 1.6, 2.2])
    }

    @Test func limitsMatchDatabaseChecks() {
        #expect(Limits.heightCm == 100...250)
        #expect(Limits.weightKg == 30...350)
        #expect(Limits.minimumAge == 18)
        #expect(Limits.earliestBirthDay == Day(year: 1900, month: 1, day: 1))
        #expect(Limits.kcal == 1...20000)
        #expect(Limits.proteinG == 0...1000)
        #expect(Limits.carbsG == 0...5000)
        #expect(Limits.fatG == 0...2000)
        #expect(Limits.foodQuantity == 0.1...10000)
        #expect(Limits.kcalPer100 == 0...900)
    }
}
