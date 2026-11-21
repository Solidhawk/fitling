import Foundation
import Testing
@testable import FitlingCore

/// A workout made on the spot for one focus (feedback 2026-11-21: "ik wil bovenlichaam trainen").
@Suite struct WorkoutBuilderTests {
    let bench = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.chest])
    let inclinePress = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.chest, .shoulders])
    let row = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.back])
    let overheadPress = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.shoulders])
    let curl = WorkoutCandidate(id: UUID(), kind: .isolation, primaryMuscles: [.biceps])
    let pushdown = WorkoutCandidate(id: UUID(), kind: .isolation, primaryMuscles: [.triceps])
    let fly = WorkoutCandidate(id: UUID(), kind: .isolation, primaryMuscles: [.chest])
    let squat = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.quads, .glutes])
    let curlLeg = WorkoutCandidate(id: UUID(), kind: .isolation, primaryMuscles: [.hamstrings])
    let calfRaise = WorkoutCandidate(id: UUID(), kind: .isolation, primaryMuscles: [.calves])

    var all: [WorkoutCandidate] { [bench, inclinePress, row, overheadPress, curl, pushdown, fly, squat, curlLeg, calfRaise] }

    func muscles(_ plan: [PlannedExercise]) -> Set<MuscleGroup> {
        Set(plan.flatMap { planned in all.first { $0.id == planned.exerciseID }?.primaryMuscles ?? [] })
    }

    @Test func anUpperBodyWorkoutTrainsEveryUpperMuscleWithCompoundsFirst() {
        let plan = WorkoutBuilder.build(.upperBody, from: all)
        #expect(muscles(plan).isSuperset(of: [.chest, .back, .shoulders, .biceps, .triceps]))
        #expect(muscles(plan).isDisjoint(with: [.quads, .glutes, .hamstrings, .calves]))
        #expect(plan.count <= WorkoutBuilder.maxExercises)
        let kinds = plan.map { planned in all.first { $0.id == planned.exerciseID }?.kind }
        let firstIsolation = kinds.firstIndex(of: .isolation) ?? kinds.count
        #expect(kinds[firstIsolation...].allSatisfy { $0 == .isolation })
        #expect(Set(plan.map(\.exerciseID)).count == plan.count)
    }

    @Test func aLowerBodyWorkoutStaysOnTheLegs() {
        let plan = WorkoutBuilder.build(.lowerBody, from: all)
        #expect(muscles(plan).isSuperset(of: [.quads, .hamstrings, .calves]))
        #expect(muscles(plan).isDisjoint(with: [.chest, .back, .shoulders, .biceps, .triceps]))
    }

    @Test func compoundsAndIsolationsGetTheirOwnSetsRepsAndRest() throws {
        let plan = WorkoutBuilder.build(.upperBody, from: all)
        let compound = try #require(plan.first { $0.exerciseID == row.id })
        #expect(compound.sets == WorkoutBuilder.compoundSets)
        #expect(compound.repRange == WorkoutBuilder.compoundReps)
        #expect(compound.restSeconds == WorkoutBuilder.compoundRestSeconds)
        let isolation = try #require(plan.first { $0.exerciseID == curl.id })
        #expect(isolation.repRange == WorkoutBuilder.isolationReps)
        #expect(isolation.restSeconds == WorkoutBuilder.isolationRestSeconds)
    }

    @Test func anExerciseNotDoneForLongerComesFirstForVariation() {
        var recentBench = bench
        recentBench.lastDone = day(2026, 11, 20)
        var olderIncline = inclinePress
        olderIncline.lastDone = day(2026, 10, 1)
        let plan = WorkoutBuilder.build(.push, from: [recentBench, olderIncline, overheadPress, pushdown])
        #expect(plan.first?.exerciseID == olderIncline.id)
    }

    @Test func withoutExercisesThereIsNoWorkout() {
        #expect(WorkoutBuilder.build(.fullBody, from: []).isEmpty)
    }

    @Test func anAlternativeTrainsTheSameMuscleTheSameWay() {
        #expect(WorkoutBuilder.alternative(to: bench, from: all) == inclinePress)
        #expect(WorkoutBuilder.alternative(to: curl, from: all) == nil)
    }

    // MARK: Stalled

    func session(_ month: Int, _ dayOfMonth: Int, kg: Double, reps: Int) -> ExerciseSession {
        ExerciseSession(day: day(2026, month, dayOfMonth), sets: [WorkingSet(weightKg: kg, reps: reps)])
    }

    @Test func anExerciseThatKeepsGettingStrongerHasNotStalled() {
        let history = [60.0, 62.5, 65, 67.5, 70].enumerated().map { session(10, 1 + $0.offset * 4, kg: $0.element, reps: 8) }
        #expect(!ProgressionEngine.isStalled(history: history))
    }

    @Test func fourSessionsWithoutBeatingTheBestBeforeThemIsAStall() {
        let history = [session(10, 1, kg: 70, reps: 8)] + (0..<4).map { session(10, 5 + $0 * 4, kg: 70, reps: 7) }
        #expect(ProgressionEngine.isStalled(history: history))
    }

    @Test func tooFewSessionsSayNothing() {
        let history = [session(10, 1, kg: 70, reps: 8)] + (0..<3).map { session(10, 5 + $0 * 4, kg: 70, reps: 7) }
        #expect(!ProgressionEngine.isStalled(history: history))
    }
}
