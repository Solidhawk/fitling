import Foundation
import Testing
@testable import FitlingCore

/// Which daily target held on a day: the rule of LocalData.targets(on:for:), now shared with the web (D-24).
@Suite struct TargetPeriodsTests {
    let fallback = NutritionTargets(kcal: 2000, proteinG: 100, carbsG: 250, fatG: 70)
    let first = NutritionTargets(kcal: 2200, proteinG: 120, carbsG: 270, fatG: 75)
    let second = NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 80)
    let moment = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theLatestPeriodOnOrBeforeTheDayHolds() {
        let periods = [
            TargetPeriodEntry(effectiveOn: day(2026, 11, 10), updatedAt: moment, targets: second),
            TargetPeriodEntry(effectiveOn: day(2026, 11, 1), updatedAt: moment, targets: first),
        ]
        #expect(TargetPeriods.targets(on: day(2026, 11, 9), periods: periods, fallback: fallback) == first)
        #expect(TargetPeriods.targets(on: day(2026, 11, 10), periods: periods, fallback: fallback) == second)
        #expect(TargetPeriods.targets(on: day(2026, 12, 25), periods: periods, fallback: fallback) == second)
    }

    @Test func beforeEveryPeriodTheProfileHolds() {
        let periods = [TargetPeriodEntry(effectiveOn: day(2026, 11, 1), updatedAt: moment, targets: first)]
        #expect(TargetPeriods.targets(on: day(2026, 10, 31), periods: periods, fallback: fallback) == fallback)
        #expect(TargetPeriods.targets(on: day(2026, 10, 31), periods: [], fallback: fallback) == fallback)
    }

    /// Two devices made a period for the same day: the newest change holds.
    @Test func onTheSameDayTheNewestHolds() {
        let periods = [
            TargetPeriodEntry(effectiveOn: day(2026, 11, 10), updatedAt: moment.addingTimeInterval(60), targets: second),
            TargetPeriodEntry(effectiveOn: day(2026, 11, 10), updatedAt: moment, targets: first),
        ]
        #expect(TargetPeriods.targets(on: day(2026, 11, 10), periods: periods, fallback: fallback) == second)
        #expect(TargetPeriods.targets(on: day(2026, 11, 10), periods: periods.reversed(), fallback: fallback) == second)
    }
}
