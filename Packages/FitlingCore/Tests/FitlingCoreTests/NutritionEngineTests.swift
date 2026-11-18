import Foundation
import Testing
@testable import FitlingCore

@Suite struct NutritionEngineTests {
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

    func plan(_ profile: BodyProfile) -> EnergyPlan {
        NutritionEngine.plan(for: profile, on: today, calendar: calendar)
    }

    func isClose(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test func bmrFollowsMifflinStJeorForEachSex() {
        #expect(isClose(NutritionEngine.bmr(weightKg: 80, heightCm: 180, age: 30, sex: .male), 1780))
        #expect(isClose(NutritionEngine.bmr(weightKg: 65, heightCm: 165, age: 40, sex: .female), 1320.25))
        #expect(isClose(NutritionEngine.bmr(weightKg: 70, heightCm: 175, age: 25, sex: .other), 1590.75))
    }

    @Test func maintenanceTargetEqualsTotalExpenditure() {
        let result = plan(profile(.male, kg: 80, cm: 180, born: date(1996, 1, 10), .moderate, .maintain))
        #expect(isClose(result.bmr, 1780))
        #expect(isClose(result.tdee, 2759))
        #expect(result.targets == NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        #expect(result.floorApplied == false)
        #expect(result.warnings.isEmpty)
    }

    @Test func muscleGainAddsTenPercent() {
        let result = plan(profile(.male, kg: 80, cm: 180, born: date(1996, 1, 10), .veryActive, .buildMuscle))
        #expect(result.targets == NutritionTargets(kcal: 3720, proteinG: 144, carbsG: 554, fatG: 103))
    }

    @Test func recompStaysJustUnderTotalExpenditure() {
        let result = plan(profile(.other, kg: 70, cm: 175, born: date(2001, 2, 2), .sedentary, .recomp))
        #expect(result.targets == NutritionTargets(kcal: 1810, proteinG: 154, carbsG: 186, fatG: 50))
        #expect(result.floorApplied == false)
    }

    @Test func neverProposesLessThanBmrTimesOnePointOne() {
        // TDEE 2136 × 0.8 = 1709, but the floor is 1780 × 1.1 = 1958.
        let result = plan(profile(.male, kg: 80, cm: 180, born: date(1996, 1, 10), .sedentary, .lose))
        #expect(result.targets == NutritionTargets(kcal: 1960, proteinG: 160, carbsG: 209, fatG: 54))
        #expect(result.floorApplied)
        #expect(Double(result.targets.kcal) >= result.bmr * NutritionEngine.floorFactor)
    }

    @Test func roundsTheFloorUpSoTheTargetStaysAboveIt() {
        // Floor 1320.25 × 1.1 = 1452.3; rounding to the nearest ten would give 1450.
        let result = plan(profile(.female, kg: 65, cm: 165, born: date(1986, 5, 1), .light, .lose))
        #expect(result.targets == NutritionTargets(kcal: 1460, proteinG: 130, carbsG: 143, fatG: 41))
        #expect(result.floorApplied)
    }

    @Test func warnsWhenTheTargetIsUnderTheCommonMinimum() {
        let result = plan(profile(.female, kg: 40, cm: 150, born: date(1951, 1, 1), .sedentary, .lose))
        #expect(result.targets.kcal == 890)
        #expect(result.warnings == [.belowCommonMinimum])
    }

    @Test func carbsNeverGoNegative() {
        let result = plan(profile(.female, kg: 30, cm: 100, born: date(1926, 1, 1), .sedentary, .recomp))
        #expect(result.targets == NutritionTargets(kcal: 300, proteinG: 66, carbsG: 0, fatG: 8))
    }

    @Test func commonMinimumDependsOnSex() {
        #expect(NutritionEngine.commonMinimumKcal(for: .male) == 1500)
        #expect(NutritionEngine.commonMinimumKcal(for: .female) == 1200)
        #expect(NutritionEngine.commonMinimumKcal(for: .other) == 1200)
    }

    @Test func manualTargetGetsAWarningPerCrossedLine() {
        func warnings(_ kcal: Int) -> Set<TargetWarning> {
            NutritionEngine.warnings(forKcal: kcal, bmr: 1780, tdee: 2759, sex: .male)
        }
        #expect(warnings(2100).isEmpty)
        #expect(warnings(2000) == [.largeDeficit])
        #expect(warnings(1900) == [.largeDeficit, .belowFloor])
        #expect(warnings(1400) == [.largeDeficit, .belowFloor, .belowCommonMinimum])
    }

    @Test func addsHalfTheWorkoutEnergyAsCarbsWhenWorkoutsCount() {
        let base = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        let result = NutritionEngine.dayTargets(base: base, workoutKcal: 400, countsWorkouts: true)
        #expect(result == NutritionTargets(kcal: 2960, proteinG: 128, carbsG: 439, fatG: 77))
    }

    @Test func leavesTheDayAloneWhenWorkoutsDoNotCount() {
        let base = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        #expect(NutritionEngine.dayTargets(base: base, workoutKcal: 400, countsWorkouts: false) == base)
    }

    @Test func ignoresWorkoutEnergyThatIsNegativeOrNotANumber() {
        let base = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        #expect(NutritionEngine.dayTargets(base: base, workoutKcal: -100, countsWorkouts: true) == base)
        #expect(NutritionEngine.dayTargets(base: base, workoutKcal: .nan, countsWorkouts: true) == base)
        #expect(NutritionEngine.dayTargets(base: base, workoutKcal: .infinity, countsWorkouts: true) == base)
    }

    @Test func macrosFollowWeightGoalAndFatShare() {
        let targets = NutritionEngine.macros(kcal: 2000, weightKg: 70, goal: .lose)
        #expect(targets == NutritionTargets(kcal: 2000, proteinG: 140, carbsG: 234, fatG: 56))
    }

    @Test func extremeProfilesStayWithinTheDatabaseLimitsAndAboveTheFloor() {
        for kg in [30.0, 350.0] {
            for cm in [100.0, 250.0] {
                for born in [date(2008, 11, 18), date(1906, 11, 18)] {
                    for sex in Sex.allCases {
                        for activity in ActivityLevel.allCases {
                            for goal in Goal.allCases {
                                let result = plan(profile(sex, kg: kg, cm: cm, born: born, activity, goal))
                                #expect(Limits.kcal.contains(result.targets.kcal))
                                #expect(Limits.proteinG.contains(result.targets.proteinG))
                                #expect(Limits.carbsG.contains(result.targets.carbsG))
                                #expect(Limits.fatG.contains(result.targets.fatG))
                                #expect(Double(result.targets.kcal) >= result.bmr * NutritionEngine.floorFactor)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func ageChangesOnTheBirthday() {
        #expect(age(birthDate: date(2000, 3, 15), on: date(2026, 3, 14), calendar: calendar) == 25)
        #expect(age(birthDate: date(2000, 3, 15), on: date(2026, 3, 15), calendar: calendar) == 26)
    }

    @Test func leapDayBirthdayCountsFromTheFirstOfMarch() {
        let born = date(2008, 2, 29)
        #expect(age(birthDate: born, on: date(2026, 2, 28), calendar: calendar) == 17)
        #expect(age(birthDate: born, on: date(2026, 3, 1), calendar: calendar) == 18)
        #expect(isAdult(birthDate: born, on: date(2026, 2, 28), calendar: calendar) == false)
        #expect(isAdult(birthDate: born, on: date(2026, 3, 1), calendar: calendar))
    }

    @Test func birthDateMustBeAdultAndNotBefore1900() {
        #expect(isValidBirthDate(date(1899, 12, 31), on: today, calendar: calendar) == false)
        #expect(isValidBirthDate(date(1900, 1, 1), on: today, calendar: calendar))
        #expect(isValidBirthDate(date(2008, 11, 18), on: today, calendar: calendar))
        #expect(isValidBirthDate(date(2008, 11, 19), on: today, calendar: calendar) == false)
    }
}
