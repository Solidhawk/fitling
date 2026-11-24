import Testing
@testable import FitlingCore

/// The days the partner is judged on, as CreatureHistory built them in the app (web phase 2).
@Suite struct DayRecordsTests {
    let first = Day(isoString: "2026-11-20")!
    let third = Day(isoString: "2026-11-22")!

    func targets(_ day: Day) -> NutritionTargets {
        day == first ? NutritionTargets(kcal: 2000, proteinG: 120, carbsG: 250, fatG: 70) : NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 80)
    }

    @Test func recordsCompareEachDayWithItsOwnTarget() {
        let records = DayRecords.build(
            entries: [LoggedEntry(day: first, kcal: 1000.4, proteinG: 50), LoggedEntry(day: first, kcal: 999.8, proteinG: nil)],
            workoutDays: [],
            targets: targets
        )
        #expect(records == [DayRecord(day: first, kcal: 2000, kcalTarget: 2000, proteinG: 50, proteinTargetG: 120, entryCount: 2, workoutCompleted: false)])
    }

    @Test func aWorkoutDayWithoutFoodStillCounts() {
        let records = DayRecords.build(entries: [LoggedEntry(day: first, kcal: 500, proteinG: 20)], workoutDays: [third], targets: targets)
        #expect(records.map(\.day) == [first, third])
        #expect(records.last == DayRecord(day: third, kcal: 0, kcalTarget: 2500, proteinG: 0, proteinTargetG: 150, entryCount: 0, workoutCompleted: true))
    }
}
