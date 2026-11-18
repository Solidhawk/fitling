import Foundation
import Testing
@testable import FitlingCore

@Suite struct EnergyCalculatorTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var today: Date { date(2026, 11, 18) }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func profile(_ sex: Sex, kg: Double, cm: Double, born: Date, _ activity: ActivityLevel, _ goal: Goal) -> BodyProfile {
        BodyProfile(birthDate: born, sex: sex, heightCm: cm, weightKg: kg, activityLevel: activity, goal: goal)
    }

    func isClose(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test func manModerateMaintain() {
        let result = calculateEnergy(for: profile(.male, kg: 80, cm: 180, born: date(1996, 1, 10), .moderate, .maintain), on: today, calendar: calendar)
        #expect(isClose(result.bmr, 1780))
        #expect(isClose(result.tdee, 2759))
        #expect(result.targets == NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        #expect(result.isBelowSafeMinimum == false)
    }

    @Test func womanLightLose() {
        let result = calculateEnergy(for: profile(.female, kg: 65, cm: 165, born: date(1986, 5, 1), .light, .lose), on: today, calendar: calendar)
        #expect(isClose(result.bmr, 1320.25))
        #expect(result.targets == NutritionTargets(kcal: 1450, proteinG: 130, carbsG: 143, fatG: 40))
    }

    @Test func otherSedentaryRecomp() {
        let result = calculateEnergy(for: profile(.other, kg: 70, cm: 175, born: date(2001, 2, 2), .sedentary, .recomp), on: today, calendar: calendar)
        #expect(isClose(result.bmr, 1590.75))
        #expect(result.targets == NutritionTargets(kcal: 1810, proteinG: 154, carbsG: 186, fatG: 50))
    }

    @Test func manVeryActiveBuildMuscle() {
        let result = calculateEnergy(for: profile(.male, kg: 80, cm: 180, born: date(1996, 1, 10), .veryActive, .buildMuscle), on: today, calendar: calendar)
        #expect(result.targets == NutritionTargets(kcal: 3720, proteinG: 144, carbsG: 554, fatG: 103))
    }

    @Test func belowSafeMinimumWarns() {
        let result = calculateEnergy(for: profile(.female, kg: 40, cm: 150, born: date(1951, 1, 1), .sedentary, .lose), on: today, calendar: calendar)
        #expect(result.targets.kcal == 770)
        #expect(result.isBelowSafeMinimum)
    }

    @Test func carbsNeverNegative() {
        let result = calculateEnergy(for: profile(.female, kg: 30, cm: 100, born: date(1926, 1, 1), .sedentary, .recomp), on: today, calendar: calendar)
        #expect(result.targets == NutritionTargets(kcal: 300, proteinG: 66, carbsG: 0, fatG: 8))
    }

    @Test func safeMinimumPerSex() {
        #expect(safeMinimumKcal(for: .male) == 1500)
        #expect(safeMinimumKcal(for: .female) == 1200)
        #expect(safeMinimumKcal(for: .other) == 1200)
    }

    @Test func ageAroundBirthday() {
        #expect(age(birthDate: date(2000, 3, 15), on: date(2026, 3, 14), calendar: calendar) == 25)
        #expect(age(birthDate: date(2000, 3, 15), on: date(2026, 3, 15), calendar: calendar) == 26)
    }

    @Test func ageLeapDay() {
        let born = date(2008, 2, 29)
        #expect(age(birthDate: born, on: date(2026, 2, 28), calendar: calendar) == 17)
        #expect(age(birthDate: born, on: date(2026, 3, 1), calendar: calendar) == 18)
        #expect(isAdult(birthDate: born, on: date(2026, 2, 28), calendar: calendar) == false)
        #expect(isAdult(birthDate: born, on: date(2026, 3, 1), calendar: calendar))
    }

    @Test func extremesStayWithinLimits() {
        for kg in [30.0, 350.0] {
            for cm in [100.0, 250.0] {
                for born in [date(2008, 11, 18), date(1906, 11, 18)] {
                    for sex in Sex.allCases {
                        for activity in ActivityLevel.allCases {
                            for goal in Goal.allCases {
                                let targets = calculateEnergy(for: profile(sex, kg: kg, cm: cm, born: born, activity, goal), on: today, calendar: calendar).targets
                                #expect(Limits.kcal.contains(targets.kcal))
                                #expect(Limits.proteinG.contains(targets.proteinG))
                                #expect(Limits.carbsG.contains(targets.carbsG))
                                #expect(Limits.fatG.contains(targets.fatG))
                            }
                        }
                    }
                }
            }
        }
    }
}
