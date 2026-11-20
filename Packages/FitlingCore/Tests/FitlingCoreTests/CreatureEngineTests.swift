import Foundation
import Testing
@testable import FitlingCore

@Suite struct CreatureEngineTests {
    let created = day(2026, 11, 1)

    func record(_ day: Day, kcal: Int, protein: Int = 0, entries: Int = 3, workout: Bool = false) -> DayRecord {
        DayRecord(day: day, kcal: kcal, kcalTarget: 2000, proteinG: protein, proteinTargetG: 120, entryCount: entries, workoutCompleted: workout)
    }

    /// One record per day from `first` to `last` in November 2026.
    func records(_ first: Int, _ last: Int, kcal: Int) -> [DayRecord] {
        (first...last).map { record(day(2026, 11, $0), kcal: kcal) }
    }

    func state(shape: Double = CreatureEngine.startShape, xp: Int = 0, processed: Int? = nil, offTarget: Int = 0) -> CreatureState {
        CreatureState(
            species: .bumblebee, colorIndex: 0, tone: .sweet, createdOn: created,
            bodyShape: shape, xp: xp, lastProcessedDay: processed.map { day(2026, 11, $0) }, offTargetDays: offTarget
        )
    }

    func condition(on dayOfMonth: Int, _ records: [DayRecord]) -> CreatureCondition {
        CreatureEngine.condition(asOf: day(2026, 11, dayOfMonth), records: records, createdOn: created)
    }

    func snapshot(_ state: CreatureState, _ records: [DayRecord], today: Int) -> CreatureSnapshot {
        CreatureEngine.snapshot(of: state, records: records, today: day(2026, 11, today))
    }

    func isClose(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.000001
    }

    // MARK: Condition

    @Test func returnsFitWhenSevenDayAverageIsWithinTenPercentOfTarget() {
        #expect(condition(on: 7, records(1, 7, kcal: 2100)) == .fit)
        #expect(condition(on: 7, records(1, 7, kcal: 2200)) == .fit)
        #expect(condition(on: 7, records(1, 7, kcal: 1800)) == .fit)
    }

    @Test func returnsTooMuchWhenSevenDayAverageIsMoreThanTenPercentOverTarget() {
        #expect(condition(on: 7, records(1, 7, kcal: 2201)) == .tooMuch)
        #expect(condition(on: 7, records(1, 7, kcal: 3000)) == .tooMuch)
    }

    @Test func returnsTiredWhenSevenDayAverageIsThirtyPercentUnderTarget() {
        let week = records(1, 7, kcal: 1400)
        #expect(condition(on: 7, week) == .tooLittle)
        #expect(snapshot(state(), week + [record(day(2026, 11, 8), kcal: 400, entries: 1)], today: 8).mood == .tired)
    }

    @Test func returnsNormalBetweenTooLittleAndFit() {
        #expect(condition(on: 7, records(1, 7, kcal: 1700)) == .normal)
        #expect(condition(on: 7, records(1, 7, kcal: 1500)) == .normal)
        #expect(condition(on: 7, records(1, 7, kcal: 1499)) == .tooLittle)
    }

    @Test func returnsNormalWithFewerThanThreeLoggedDays() {
        #expect(condition(on: 7, records(6, 7, kcal: 3000)) == .normal)
        #expect(condition(on: 7, records(5, 7, kcal: 3000)) == .tooMuch)
    }

    @Test func leavesBarelyLoggedDaysOutOfTheAverage() {
        let full = records(1, 4, kcal: 2000)
        let onlyBreakfast = (5...7).map { record(day(2026, 11, $0), kcal: 300, entries: 1) }
        #expect(condition(on: 7, full + onlyBreakfast) == .fit)
    }

    @Test func looksOnlyAtTheLastSevenDays() {
        let earlier = records(1, 7, kcal: 3000)
        let lastWeek = records(8, 14, kcal: 2000)
        #expect(condition(on: 14, earlier + lastWeek) == .fit)
    }

    // MARK: Sleeping

    @Test func fallsAsleepAfterThreeDaysWithoutLogs() {
        let logs = records(1, 10, kcal: 2000)
        let onThirdEmptyDay = snapshot(state(processed: 12), logs, today: 13)
        #expect(onThirdEmptyDay.condition != .asleep)
        #expect(onThirdEmptyDay.mood == .hungry)

        let after = snapshot(state(processed: 13), logs, today: 14)
        #expect(after.condition == .asleep)
        #expect(after.mood == .asleep)
        #expect(after.energy == 0)
    }

    @Test func wakesUpAfterOneLoggedMeal() {
        let logs = records(1, 10, kcal: 2000) + [record(day(2026, 11, 14), kcal: 400, entries: 1)]
        let result = snapshot(state(processed: 13), logs, today: 14)
        #expect(result.condition != .asleep)
        #expect(result.mood != .asleep)
        #expect(result.energy > 0)
    }

    @Test func newCreatureIsAwakeUntilThreeDaysHavePassedWithoutLogs() {
        #expect(snapshot(state(), [], today: 1).mood == .content)
        #expect(snapshot(state(), [], today: 3).mood == .hungry)
        #expect(snapshot(state(), [], today: 4).condition == .asleep)
    }

    @Test func isNotHungryInTheMorningAfterALoggedDay() {
        #expect(snapshot(state(processed: 7), records(1, 7, kcal: 2000), today: 8).mood == .happy)
    }

    // MARK: Body shape

    @Test func bodyShapeMovesAtMostOneStepPerDay() {
        let update = CreatureEngine.advance(state(processed: 6), records: records(1, 7, kcal: 3000), today: day(2026, 11, 8))
        #expect(isClose(update.state.bodyShape, 0.35))
        #expect(update.state.lastProcessedDay == day(2026, 11, 7))
    }

    @Test func growsRounderGraduallyWhileEatingTooMuch() {
        // Days 1 and 2 have too little history; days 3...10 each add one step.
        let update = CreatureEngine.advance(state(), records: records(1, 10, kcal: 3000), today: day(2026, 11, 11))
        #expect(isClose(update.state.bodyShape, 0.7))
    }

    @Test func returnsTowardsTheFitShapeWhileEatingOnTarget() {
        let update = CreatureEngine.advance(state(shape: 0.6, processed: 10), records: records(4, 13, kcal: 2000), today: day(2026, 11, 14))
        #expect(isClose(update.state.bodyShape, 0.45))
    }

    @Test func bodyShapeStaysBetweenZeroAndOne() {
        let lean = CreatureEngine.advance(state(shape: 0.02, processed: 7), records: records(1, 8, kcal: 2000), today: day(2026, 11, 9))
        #expect(lean.state.bodyShape == 0)
        let round = CreatureEngine.advance(state(shape: 0.98, processed: 7), records: records(1, 8, kcal: 4000), today: day(2026, 11, 9))
        #expect(round.state.bodyShape == 1)
    }

    @Test func eatingTooLittleNeverMakesTheCreatureSlimmer() {
        let update = CreatureEngine.advance(state(shape: 0.6), records: records(1, 10, kcal: 1400), today: day(2026, 11, 11))
        #expect(update.state.bodyShape == 0.6)
        #expect(update.state.xp == 10 * 10)
    }

    @Test func mildOvereatingSettlesBetweenStartAndRound() {
        // 115 % of the target aims at 0.5 + 0.5 × (0.05 / 0.40) = 0.5625.
        let fromRound = CreatureEngine.advance(state(shape: 0.9, processed: 7), records: records(1, 8, kcal: 2300), today: day(2026, 11, 9))
        #expect(isClose(fromRound.state.bodyShape, 0.85))
        let nearby = CreatureEngine.advance(state(shape: 0.55, processed: 7), records: records(1, 8, kcal: 2300), today: day(2026, 11, 9))
        #expect(isClose(nearby.state.bodyShape, 0.5625))
    }

    @Test func sleepingDoesNotChangeTheShape() {
        let update = CreatureEngine.advance(state(shape: 0.8, processed: 10), records: records(1, 10, kcal: 3000), today: day(2026, 11, 20))
        // Days 11 and 12 still fall in a "too much" week; from day 13 the creature sleeps.
        #expect(isClose(update.state.bodyShape, 0.9))
        #expect(update.state.lastProcessedDay == day(2026, 11, 19))
    }

    // MARK: XP and levels

    @Test func awardsXPForLoggingStayingOnTargetProteinAndTraining() {
        let breakdown = CreatureEngine.xp(for: record(created, kcal: 2000, protein: 130, workout: true))
        #expect(breakdown == XPBreakdown(logging: 10, withinTarget: 40, protein: 20, workout: 30))
        #expect(breakdown.total == 100)
    }

    @Test func givesNoTargetXPForEatingTooLittleOrTooMuch() {
        #expect(CreatureEngine.xp(for: record(created, kcal: 1400)) == XPBreakdown(logging: 10))
        #expect(CreatureEngine.xp(for: record(created, kcal: 2600)) == XPBreakdown(logging: 10))
    }

    @Test func aWorkoutCountsEvenWithoutFoodLogs() {
        #expect(CreatureEngine.xp(for: record(created, kcal: 0, entries: 0, workout: true)) == XPBreakdown(workout: 30))
        #expect(CreatureEngine.xp(for: record(created, kcal: 0, protein: 0, entries: 0)) == XPBreakdown())
    }

    @Test func neverCountsADayTwice() {
        let logs = records(1, 7, kcal: 2000)
        let first = CreatureEngine.advance(state(), records: logs, today: day(2026, 11, 8))
        let second = CreatureEngine.advance(first.state, records: logs, today: day(2026, 11, 8))
        #expect(first.state.xp == 7 * 50)
        #expect(second.state == first.state)
        #expect(second.events.isEmpty)
    }

    @Test func todayIsNotProcessedUntilItIsOver() {
        let update = CreatureEngine.advance(state(), records: records(1, 1, kcal: 2000), today: created)
        #expect(update.state.xp == 0)
        #expect(update.state.lastProcessedDay == nil)
    }

    @Test func catchesUpOnDaysTheAppWasNotOpened() {
        let update = CreatureEngine.advance(state(processed: 5), records: records(1, 8, kcal: 2000), today: day(2026, 11, 20))
        #expect(update.state.lastProcessedDay == day(2026, 11, 19))
        #expect(update.state.xp == 3 * 50)
    }

    @Test func awardsRecoveryBonusAfterAWeekOfTooMuchBackToFit() {
        let logs = records(1, 10, kcal: 3000) + records(11, 25, kcal: 2000)
        let update = CreatureEngine.advance(state(), records: logs, today: day(2026, 11, 26))
        #expect(update.events.filter { $0 == .recoveryBonus(xp: 150) }.count == 1)
        // 10 days of logging only, 15 days on target, one bonus.
        #expect(update.state.xp == 10 * 10 + 15 * 50 + 150)
        #expect(update.state.offTargetDays == 0)
    }

    @Test func awardsRecoveryBonusAfterAWeekOfTooLittleBackToFit() {
        let logs = records(1, 10, kcal: 1400) + records(11, 25, kcal: 2000)
        let update = CreatureEngine.advance(state(), records: logs, today: day(2026, 11, 26))
        #expect(update.events.contains(.recoveryBonus(xp: 150)))
    }

    @Test func givesNoRecoveryBonusAfterOnlyAFewDaysOffTarget() {
        // "Too much" from day 3 up to and including day 8: six days.
        let logs = records(1, 3, kcal: 3000) + records(4, 20, kcal: 2000)
        let update = CreatureEngine.advance(state(), records: logs, today: day(2026, 11, 21))
        #expect(update.events.contains(.recoveryBonus(xp: 150)) == false)
    }

    @Test func levelsFollowTheXPCurve() {
        #expect(CreatureEngine.xpRequired(forLevel: 1) == 0)
        #expect(CreatureEngine.xpRequired(forLevel: 2) == 100)
        #expect(CreatureEngine.xpRequired(forLevel: 3) == 300)
        #expect(CreatureEngine.xpRequired(forLevel: 5) == 1000)
        #expect(CreatureEngine.level(forXP: 0) == 1)
        #expect(CreatureEngine.level(forXP: 99) == 1)
        #expect(CreatureEngine.level(forXP: 100) == 2)
        #expect(CreatureEngine.level(forXP: 299) == 2)
        #expect(CreatureEngine.level(forXP: 300) == 3)
        #expect(CreatureEngine.level(forXP: -5) == 1)
        #expect(CreatureEngine.level(forXP: .max) == CreatureEngine.maxLevel)
    }

    @Test func reportsLevelUpsAndWhatTheyUnlock() {
        let logs = [record(created, kcal: 2000, protein: 130, workout: true)]
        let toTwo = CreatureEngine.advance(state(xp: 90), records: logs, today: day(2026, 11, 2))
        #expect(toTwo.state.xp == 190)
        #expect(toTwo.events == [.leveledUp(to: 2), .unlockedItem(.scarf)])

        let toFive = CreatureEngine.advance(state(xp: 990), records: logs, today: day(2026, 11, 2))
        #expect(toFive.events == [.leveledUp(to: 5), .unlockedColor(index: 3)])
    }

    @Test func growthStageFollowsLevel() {
        #expect([1, 2, 3, 5, 6, 10, 14, 15, 21, 22, 40].map(CreatureEngine.growthStage(forLevel:)) == [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5])
    }

    @Test func sixteenSpeciesWithTheirDatabaseValues() {
        #expect(Species.allCases.map(\.rawValue) == [
            "bumblebee", "mole", "frog", "owl", "hedgehog", "snail", "axolotl", "seal",
            "penguin", "turtle", "rabbit", "raccoon", "ladybird", "octopus", "squirrel", "lamb",
        ])
        #expect(CreatureEngine.growthLevels.count == 6)
    }

    @Test func itemsAndColorsUnlockPerLevel() {
        #expect(CreatureEngine.unlockedItems(atLevel: 1).isEmpty)
        #expect(CreatureEngine.unlockedItems(atLevel: 4) == [.scarf, .cap])
        #expect(CreatureEngine.unlockedItems(atLevel: 15) == CreatureItem.allCases)
        #expect([1, 4, 5, 11, 12].map(CreatureEngine.unlockedColorCount(atLevel:)) == [3, 3, 4, 4, 5])
    }

    // MARK: Snapshot

    @Test func snapshotCarriesLevelProgressAndUnlocks() {
        let result = snapshot(state(xp: 450, processed: 7), records(1, 7, kcal: 2000), today: 8)
        #expect(result.species == .bumblebee)
        #expect(result.level == 3)
        #expect(result.xp == 450)
        #expect(result.xpIntoLevel == 150)
        #expect(result.xpForNextLevel == 300)
        #expect(result.growthStage == 1)
        #expect(result.unlockedItems == [.scarf])
        #expect(result.unlockedColorCount == 3)
    }

    @Test func energyIsHighestWhenFitAndLowWhenOffTarget() {
        let fit = snapshot(state(processed: 7), records(1, 7, kcal: 2000), today: 8)
        let normal = snapshot(state(processed: 7), records(1, 7, kcal: 1700), today: 8)
        let tooMuch = snapshot(state(processed: 7), records(1, 7, kcal: 3000), today: 8)
        let tooLittle = snapshot(state(processed: 7), records(1, 7, kcal: 1400), today: 8)
        #expect(fit.energy == 1)
        #expect(fit.mood == .happy)
        #expect(normal.energy < fit.energy)
        #expect(normal.mood == .content)
        #expect(tooMuch.energy < normal.energy)
        #expect(tooMuch.mood == .sluggish)
        #expect(tooLittle.energy < normal.energy)
    }

    @Test func showsTrainingFromTodayOrYesterday() {
        let trainedYesterday = records(1, 6, kcal: 2000) + [record(day(2026, 11, 7), kcal: 2000, workout: true)]
        #expect(snapshot(state(processed: 7), trainedYesterday, today: 8).trainedRecently)
        #expect(snapshot(state(processed: 8), trainedYesterday, today: 9).trainedRecently == false)
    }

    // MARK: Messages

    @Test func messageKeysFollowTopicToneAndVariant() {
        #expect(CreatureEngine.messageKeys(topic: .hungry, tone: .coach) == [
            "creature.message.hungry.coach.1", "creature.message.hungry.coach.2", "creature.message.hungry.coach.3",
        ])
        #expect(CreatureEngine.messageKeys(topic: .tooMuch, tone: .sweet).first == "creature.message.tooMuch.sweet.1")
    }

    @Test func messageRotatesSoTwoDaysInARowDiffer() {
        let keys = (16...18).map { CreatureEngine.messageKey(topic: .fit, tone: .funny, on: day(2026, 11, $0)) }
        #expect(Set(keys).count == 3)
        let all = CreatureEngine.messageKeys(topic: .fit, tone: .funny)
        #expect(keys.allSatisfy { all.contains($0) })
        #expect(CreatureEngine.messageKey(topic: .fit, tone: .funny, on: day(2026, 11, 16)) == keys[0])
    }

    @Test func topicFollowsMoodBeforeCondition() {
        #expect(CreatureEngine.topic(for: snapshot(state(), [], today: 3)) == .hungry)
        #expect(CreatureEngine.topic(for: snapshot(state(), [], today: 4)) == .asleep)
        #expect(CreatureEngine.topic(for: snapshot(state(processed: 7), records(1, 7, kcal: 3000), today: 8)) == .tooMuch)
        #expect(CreatureEngine.topic(for: snapshot(state(processed: 7), records(1, 7, kcal: 2000), today: 8)) == .fit)
    }
}
