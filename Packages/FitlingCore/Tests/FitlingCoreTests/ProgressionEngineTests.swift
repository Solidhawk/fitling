import Foundation
import Testing
@testable import FitlingCore

@Suite struct ProgressionEngineTests {
    let today = day(2026, 11, 18)
    let barbell = ExerciseRules(kind: .compound, repRange: 8...12, targetSets: 3, stepKg: 2.5)

    func session(_ dayOfMonth: Int, month: Int = 11, kg: Double, reps: [Int], rpe: Double? = 8) -> ExerciseSession {
        ExerciseSession(day: day(2026, month, dayOfMonth), sets: reps.map { WorkingSet(weightKg: kg, reps: $0, rpe: rpe) })
    }

    func advise(_ history: [ExerciseSession], _ rules: ExerciseRules? = nil) -> ProgressionAdvice {
        ProgressionEngine.advise(history: history, rules: rules ?? barbell, today: today)
    }

    // MARK: Double progression

    @Test func asksForAStartingWeightWithoutHistory() {
        #expect(advise([]) == .findStartingWeight)
    }

    @Test func advisesMoreWeightWhenEverySetReachesTheTopAtRpeEightOrLess() {
        #expect(advise([session(16, kg: 60, reps: [12, 12, 12])]) == .increase(toKg: 62.5))
    }

    @Test func keepsTheWeightWhenOneSetStaysUnderTheTop() {
        #expect(advise([session(16, kg: 60, reps: [12, 12, 11])]) == .keepGoing(weightKg: 60))
    }

    @Test func keepsTheWeightWhenASetWasHarderThanRpeEight() {
        var hard = session(16, kg: 60, reps: [12, 12, 12])
        hard.sets[2].rpe = 9
        #expect(advise([hard]) == .keepGoing(weightKg: 60))
    }

    @Test func treatsASetWithoutRpeAsEasyEnough() {
        #expect(advise([session(16, kg: 60, reps: [12, 12, 12], rpe: nil)]) == .increase(toKg: 62.5))
    }

    @Test func keepsTheWeightWhenFewerSetsWereDoneThanPlanned() {
        #expect(advise([session(16, kg: 60, reps: [12, 12])]) == .keepGoing(weightKg: 60))
    }

    @Test func looksAtTheHeaviestSetsWhenLighterBackOffSetsFollow() {
        var withBackOff = session(16, kg: 60, reps: [12, 12, 12])
        withBackOff.sets.append(WorkingSet(weightKg: 50, reps: 15, rpe: 9))
        #expect(advise([withBackOff]) == .increase(toKg: 62.5))
    }

    @Test func usesTheLatestSessionWhateverTheOrderOfTheHistory() {
        let older = session(9, kg: 57.5, reps: [12, 12, 12])
        let latest = session(16, kg: 60, reps: [10, 9, 9])
        #expect(advise([latest, older]) == .keepGoing(weightKg: 60))
        #expect(advise([older, latest]) == .keepGoing(weightKg: 60))
    }

    // MARK: Weight steps

    @Test func isolationGoesUpByTheSmallestStepOfAtLeastOneKilo() {
        let cable = ExerciseRules(kind: .isolation, repRange: 10...15, targetSets: 3, stepKg: 1)
        #expect(advise([session(16, kg: 20, reps: [15, 15, 15])], cable) == .increase(toKg: 21))
        let fine = ExerciseRules(kind: .isolation, repRange: 10...15, targetSets: 3, stepKg: 0.5)
        #expect(advise([session(16, kg: 20, reps: [15, 15, 15])], fine) == .increase(toKg: 21))
    }

    @Test func dumbbellsGoUpPerTwoKilo() {
        let dumbbell = ExerciseRules(kind: .isolation, repRange: 10...15, targetSets: 3, stepKg: 2)
        #expect(advise([session(16, kg: 30, reps: [15, 15, 15])], dumbbell) == .increase(toKg: 32))
    }

    @Test func asksForExtraRepsFirstWhenTheNextStepIsABigJump() {
        // 8 kg to 10 kg is 25 % more: first two reps past the range on every set.
        let dumbbell = ExerciseRules(kind: .isolation, repRange: 10...15, targetSets: 3, stepKg: 2)
        #expect(advise([session(16, kg: 8, reps: [15, 15, 15])], dumbbell) == .addRepsFirst(weightKg: 8, targetReps: 17))
        #expect(advise([session(16, kg: 8, reps: [17, 17, 17])], dumbbell) == .increase(toKg: 10))
    }

    @Test func machineStackGoesUpPerFiveKilo() {
        let machine = ExerciseRules(kind: .compound, repRange: 8...12, targetSets: 3, stepKg: 5)
        #expect(advise([session(16, kg: 100, reps: [12, 12, 12])], machine) == .increase(toKg: 105))
        #expect(advise([session(16, kg: 40, reps: [12, 12, 12])], machine) == .addRepsFirst(weightKg: 40, targetReps: 14))
    }

    // MARK: Going back

    @Test func advisesLessWeightAfterTwoSessionsInARowUnderTheRange() {
        let history = [session(13, kg: 60, reps: [7, 6, 6]), session(16, kg: 60, reps: [7, 7, 6])]
        #expect(advise(history) == .reduce(toKg: 52.5))
    }

    @Test func oneSessionUnderTheRangeIsNotEnoughToGoBack() {
        let history = [session(13, kg: 60, reps: [9, 9, 8]), session(16, kg: 60, reps: [7, 7, 6])]
        #expect(advise(history) == .keepGoing(weightKg: 60))
    }

    @Test func oneWeakSetDoesNotMakeASessionUnderTheRange() {
        let history = [session(13, kg: 60, reps: [9, 8, 7]), session(16, kg: 60, reps: [9, 8, 7])]
        #expect(advise(history) == .keepGoing(weightKg: 60))
    }

    @Test func sessionsOnEitherSideOfABreakAreNotInARow() {
        let history = [session(20, month: 10, kg: 60, reps: [7, 6, 6]), session(16, kg: 60, reps: [7, 7, 6])]
        #expect(advise(history) == .keepGoing(weightKg: 60))
    }

    @Test func nothingLighterThanTheSmallestWeightIsAdvised() {
        let history = [session(13, kg: 2.5, reps: [6, 6, 6]), session(16, kg: 2.5, reps: [6, 6, 6])]
        #expect(advise(history) == .keepGoing(weightKg: 2.5))
    }

    // MARK: Missed weeks

    @Test func easesBackInAfterTwoWeeksAway() {
        #expect(advise([session(1, kg: 60, reps: [10, 10, 10])]) == .easeBackIn(toKg: 52.5))
    }

    @Test func easesBackInFurtherAfterFourWeeksAway() {
        #expect(advise([session(10, month: 10, kg: 60, reps: [10, 10, 10])]) == .easeBackIn(toKg: 47.5))
    }

    @Test func aBreakOfLessThanTwoWeeksChangesNothing() {
        #expect(advise([session(5, kg: 60, reps: [10, 10, 10])]) == .keepGoing(weightKg: 60))
    }

    // MARK: Body weight

    @Test func bodyWeightAtTheTopWithoutExtraLoadShouldGetHarder() {
        let pullUp = ExerciseRules(kind: .compound, loadType: .bodyweight, repRange: 6...10, targetSets: 3, stepKg: 2.5)
        #expect(advise([session(16, kg: 0, reps: [10, 10, 10])], pullUp) == .makeHarder)
    }

    @Test func weightedBodyWeightExerciseGoesUpByAStepWithoutTheBigJumpRule() {
        let pullUp = ExerciseRules(kind: .compound, loadType: .bodyweight, repRange: 6...10, targetSets: 3, stepKg: 2.5)
        #expect(advise([session(16, kg: 10, reps: [10, 10, 10])], pullUp) == .increase(toKg: 12.5))
    }

    @Test func bodyWeightUnderTheRangeTwiceShouldGetEasier() {
        let pullUp = ExerciseRules(kind: .compound, loadType: .bodyweight, repRange: 6...10, targetSets: 3, stepKg: 2.5)
        let unloaded = [session(13, kg: 0, reps: [4, 4, 3]), session(16, kg: 0, reps: [5, 4, 3])]
        #expect(advise(unloaded, pullUp) == .makeEasier)
        let loaded = [session(13, kg: 2.5, reps: [4, 4, 3]), session(16, kg: 2.5, reps: [5, 4, 3])]
        #expect(advise(loaded, pullUp) == .reduce(toKg: 0))
    }

    @Test func bodyWeightAfterABreakKeepsGoingWithoutExtraLoad() {
        let pullUp = ExerciseRules(kind: .compound, loadType: .bodyweight, repRange: 6...10, targetSets: 3, stepKg: 2.5)
        #expect(advise([session(1, kg: 0, reps: [8, 8, 8])], pullUp) == .keepGoing(weightKg: 0))
    }

    // MARK: One-rep max and records

    @Test func estimatesOneRepMaxWithEpley() throws {
        let estimate = try #require(ProgressionEngine.estimatedOneRepMax(weightKg: 100, reps: 5))
        #expect(abs(estimate - 116.6667) < 0.001)
        #expect(ProgressionEngine.estimatedOneRepMax(weightKg: 100, reps: 1) == 100)
        #expect(ProgressionEngine.estimatedOneRepMax(weightKg: 60, reps: 12) == 84)
    }

    @Test func givesNoOneRepMaxForLongSetsOrEmptyInput() {
        #expect(ProgressionEngine.estimatedOneRepMax(weightKg: 100, reps: 13) == nil)
        #expect(ProgressionEngine.estimatedOneRepMax(weightKg: 100, reps: 0) == nil)
        #expect(ProgressionEngine.estimatedOneRepMax(weightKg: 0, reps: 5) == nil)
    }

    @Test func detectsWeightOneRepMaxAndRepRecords() {
        let history = [session(9, kg: 60, reps: [10, 10, 10])]
        let new = ExerciseSession(day: day(2026, 11, 16), sets: [
            WorkingSet(weightKg: 62.5, reps: 10), WorkingSet(weightKg: 60, reps: 12),
        ])
        #expect(ProgressionEngine.personalRecords(in: new, history: history) == [
            .weight(kg: 62.5), .estimatedOneRepMax(kg: 84), .reps(count: 12, atKg: 60),
        ])
    }

    @Test func firstSessionSetsTheBaselineWithoutRecords() {
        #expect(ProgressionEngine.personalRecords(in: session(16, kg: 60, reps: [10, 10, 10]), history: []).isEmpty)
    }

    @Test func reportsNoRecordWhenNothingImproved() {
        let history = [session(9, kg: 60, reps: [10, 10, 10])]
        #expect(ProgressionEngine.personalRecords(in: session(16, kg: 60, reps: [10, 9, 9]), history: history).isEmpty)
    }

    // MARK: Volume

    @Test func countsASetFullyForPrimaryAndHalfForSecondaryMuscles() {
        let bench = LoggedExercise(
            day: day(2026, 11, 16), primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders],
            sets: Array(repeating: WorkingSet(weightKg: 60, reps: 10), count: 3)
        )
        let row = LoggedExercise(
            day: day(2026, 11, 22), primaryMuscles: [.back], secondaryMuscles: [.biceps],
            sets: Array(repeating: WorkingSet(weightKg: 50, reps: 8), count: 2)
        )
        let week = ProgressionEngine.weeklyVolume([bench, row])[day(2026, 11, 16)]
        #expect(week?[.chest] == MuscleVolume(sets: 3, tonnageKg: 1800))
        #expect(week?[.triceps] == MuscleVolume(sets: 1.5, tonnageKg: 900))
        #expect(week?[.shoulders] == MuscleVolume(sets: 1.5, tonnageKg: 900))
        #expect(week?[.back] == MuscleVolume(sets: 2, tonnageKg: 800))
        #expect(week?[.biceps] == MuscleVolume(sets: 1, tonnageKg: 400))
        #expect(week?[.quads] == nil)
    }

    @Test func startsANewWeekOnMonday() {
        let sunday = LoggedExercise(day: day(2026, 11, 22), primaryMuscles: [.quads], sets: [WorkingSet(weightKg: 100, reps: 5)])
        let monday = LoggedExercise(day: day(2026, 11, 23), primaryMuscles: [.quads], sets: [WorkingSet(weightKg: 100, reps: 5)])
        let volume = ProgressionEngine.weeklyVolume([sunday, monday])
        #expect(volume.keys.sorted() == [day(2026, 11, 16), day(2026, 11, 23)])
        #expect(volume[day(2026, 11, 23)]?[.quads] == MuscleVolume(sets: 1, tonnageKg: 500))
    }
}
