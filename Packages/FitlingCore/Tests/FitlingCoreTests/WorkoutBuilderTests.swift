import Foundation
import Testing
@testable import FitlingCore

/// A workout made on the spot for one focus (feedback 2026-11-21: "ik wil bovenlichaam trainen") and
/// one duration (feedback 2026-11-22: say how long you want to train; keep the main lifts).
@Suite struct WorkoutBuilderTests {
    let all: [WorkoutCandidate]
    private let names: [UUID: String]

    /// A gym with, per muscle, four compounds (none for the small muscles) and four isolation exercises. The first
    /// compound of a large muscle and the first isolation of a small one are in the ready-made programmes, and for
    /// the back and quads the second compound too.
    init() {
        let small: Set<MuscleGroup> = [.biceps, .triceps, .forearms, .calves, .core]
        var all: [WorkoutCandidate] = []
        var names: [UUID: String] = [:]
        var rank = 0
        for muscle in MuscleGroup.allCases {
            for kind in ExerciseKind.allCases where !(kind == .compound && small.contains(muscle)) {
                for index in 1...4 {
                    let isMain = (kind == .compound) != small.contains(muscle)
                    let listed = isMain && (index == 1 || (index == 2 && (muscle == .back || muscle == .quads)))
                    let id = UUID()
                    all.append(WorkoutCandidate(id: id, kind: kind, primaryMuscles: [muscle], preference: listed ? rank : nil))
                    names[id] = "\(muscle.rawValue)-\(kind.rawValue)-\(index)"
                    if listed { rank += 1 }
                }
            }
        }
        self.all = all
        self.names = names
    }

    func candidate(_ name: String) throws -> WorkoutCandidate {
        try #require(all.first { names[$0.id] == name })
    }

    func shown(_ plan: WorkoutPlan) -> [String] {
        plan.exercises.compactMap { names[$0.exerciseID] }
    }

    func muscles(_ plan: WorkoutPlan) -> Set<MuscleGroup> {
        Set(plan.exercises.flatMap { planned in all.first { $0.id == planned.exerciseID }?.primaryMuscles ?? [] })
    }

    /// The same choice `times` in a row, each workout done as planned.
    func run(_ focus: TrainingFocus, minutes: Int, times: Int) -> [WorkoutPlan] {
        var history: [[UUID]] = []
        return (0..<times).map { _ in
            let plan = WorkoutBuilder.plan(focus, minutes: minutes, from: all, history: history)
            history.insert(plan.exercises.map(\.exerciseID), at: 0)
            return plan
        }
    }

    // MARK: What is trained

    @Test func anUpperBodyWorkoutTrainsEveryUpperMuscleWithCompoundsFirst() {
        let plan = WorkoutBuilder.plan(.upperBody, minutes: 60, from: all, history: [])
        #expect(muscles(plan).isSuperset(of: [.chest, .back, .shoulders, .biceps, .triceps]))
        #expect(muscles(plan).isDisjoint(with: [.quads, .glutes, .hamstrings, .calves]))
        let kinds = plan.exercises.map { planned in all.first { $0.id == planned.exerciseID }?.kind }
        let firstIsolation = kinds.firstIndex(of: .isolation) ?? kinds.count
        #expect(kinds[firstIsolation...].allSatisfy { $0 == .isolation })
        #expect(Set(plan.exercises.map(\.exerciseID)).count == plan.exercises.count)
    }

    @Test func aLowerBodyWorkoutStaysOnTheLegs() {
        let plan = WorkoutBuilder.plan(.lowerBody, minutes: 60, from: all, history: [])
        #expect(muscles(plan).isSuperset(of: [.quads, .hamstrings, .glutes, .calves]))
        #expect(muscles(plan).isDisjoint(with: [.chest, .back, .shoulders, .biceps, .triceps]))
    }

    @Test func aPullWorkoutHasTwoCompoundsForTheBack() {
        let plan = WorkoutBuilder.plan(.pull, minutes: 45, from: all, history: [])
        #expect(shown(plan).prefix(2) == ["back-compound-1", "back-compound-2"])
    }

    @Test func compoundsAndIsolationsGetTheirOwnRepsAndRest() throws {
        let plan = WorkoutBuilder.plan(.upperBody, minutes: 60, from: all, history: [])
        let row = try candidate("back-compound-1"), curl = try candidate("biceps-isolation-1")
        let compound = try #require(plan.exercises.first { $0.exerciseID == row.id })
        #expect(compound.sets == 3)
        #expect(compound.repRange == WorkoutBuilder.compoundReps)
        #expect(compound.restSeconds == WorkoutBuilder.compoundRestSeconds)
        let isolation = try #require(plan.exercises.first { $0.exerciseID == curl.id })
        #expect(isolation.repRange == WorkoutBuilder.isolationReps)
        #expect(isolation.restSeconds == WorkoutBuilder.isolationRestSeconds)
    }

    @Test func withoutExercisesThereIsNoWorkout() {
        let plan = WorkoutBuilder.plan(.fullBody, minutes: 60, from: [], history: [])
        #expect(plan.exercises.isEmpty)
        #expect(plan.seconds == 0)
    }

    // MARK: How long

    @Test func theChoicesRunFromAQuarterToAnHourAndAHalf() {
        #expect(WorkoutBuilder.durations == [15, 20, 30, 45, 60, 75, 90])
        #expect(WorkoutBuilder.durations.contains(WorkoutBuilder.defaultMinutes))
    }

    @Test func aWorkoutNeverTakesLongerThanAsked() {
        for focus in TrainingFocus.allCases {
            for minutes in WorkoutBuilder.durations {
                for plan in run(focus, minutes: minutes, times: 12) {
                    #expect(!plan.exercises.isEmpty, "\(focus) \(minutes)")
                    #expect(plan.seconds > 0 && plan.seconds <= minutes * 60, "\(focus) \(minutes): \(plan.seconds)")
                    #expect(plan.exercises.count <= WorkoutBuilder.maxExercises, "\(focus) \(minutes)")
                }
            }
        }
    }

    @Test func moreTimeMeansMoreWork() {
        let sets = [15, 30, 60, 90].map { minutes in
            WorkoutBuilder.plan(.fullBody, minutes: minutes, from: all, history: []).exercises.map(\.sets).reduce(0, +)
        }
        #expect(sets == sets.sorted())
        #expect(Set(sets).count == sets.count)
    }

    @Test func theEstimateCountsWarmUpSetsRestAndChangingOver() {
        let bench = WorkoutCandidate(id: UUID(), kind: .compound, primaryMuscles: [.chest])
        // Warm-up 180, changing over 60, warm-up sets 120, four sets of 45 and three rests of 90.
        let short = WorkoutBuilder.plan(.push, minutes: 15, from: [bench], history: [])
        #expect(short.exercises.map(\.sets) == [4])
        #expect(short.seconds == 810)
        #expect(short.roundedMinutes == 14)
        // Warm-up 300, changing over 90, warm-up sets 120, four sets of 45 and three rests of 150.
        let long = WorkoutBuilder.plan(.push, minutes: 60, from: [bench], history: [])
        #expect(long.seconds == 1140)
        #expect(long.leavesTimeOver)
        #expect(!short.leavesTimeOver)
    }

    @Test func aShortWorkoutHasShorterRestAndFewerSets() throws {
        let plan = WorkoutBuilder.plan(.fullBody, minutes: 15, from: all, history: [])
        let first = try #require(plan.exercises.first)
        #expect(first.sets == 2)
        #expect(first.restSeconds == WorkoutBuilder.shortCompoundRestSeconds)
        #expect(WorkoutBuilder.shortCompoundRestSeconds < WorkoutBuilder.compoundRestSeconds)
    }

    @Test func whatDoesNotFitIsNamedAndComesFirstNextTime() throws {
        let plans = run(.fullBody, minutes: 15, times: 3)
        let first = try #require(plans.first)
        #expect(first.leftOut == [.back, .hamstrings, .shoulders])
        #expect(muscles(plans[1]).isSubset(of: [.back, .hamstrings, .shoulders]))
        #expect(Set(plans.flatMap { muscles($0) }).isSuperset(of: TrainingFocus.fullBody.muscles))
    }

    @Test func withEnoughTimeNothingIsLeftOut() {
        #expect(WorkoutBuilder.plan(.fullBody, minutes: 60, from: all, history: []).leftOut.isEmpty)
    }

    // MARK: Keep and vary

    @Test func aFirstWorkoutStartsWithTheExercisesOfTheReadyMadeProgrammes() {
        let plan = WorkoutBuilder.plan(.fullBody, minutes: 45, from: all, history: [])
        #expect(shown(plan) == ["quads-compound-1", "chest-compound-1", "back-compound-1", "hamstrings-compound-1", "shoulders-compound-1"])
    }

    @Test func aMainExerciseStaysEightWorkoutsAndThenChanges() {
        let plans = run(.fullBody, minutes: 45, times: 9).map { shown($0).first ?? "" }
        #expect(plans.prefix(8).allSatisfy { $0 == "quads-compound-1" })
        // The next one from the programmes before one that is in none.
        #expect(plans.last == "quads-compound-2")
    }

    /// The bug this replaced: with a long list every workout had new exercises, so nothing got stronger.
    @Test func extraExercisesNeverPushTheMainExerciseOut() {
        for focus in TrainingFocus.allCases {
            for minutes in WorkoutBuilder.durations where minutes >= 45 {
                let firsts = run(focus, minutes: minutes, times: 8).map { shown($0).first ?? "" }
                #expect(Set(firsts).count == 1, "\(focus) \(minutes): \(firsts)")
            }
        }
    }

    @Test func workoutsForOtherMusclesInBetweenDoNotCount() throws {
        let squat = try candidate("quads-compound-1"), row = try candidate("back-compound-1")
        let seven = Array(repeating: [[row.id], [squat.id]], count: 7).flatMap { $0 }
        #expect(shown(WorkoutBuilder.plan(.lowerBody, minutes: 45, from: all, history: seven)).first == "quads-compound-1")
        let eight = Array(repeating: [[row.id], [squat.id]], count: 8).flatMap { $0 }
        #expect(shown(WorkoutBuilder.plan(.lowerBody, minutes: 45, from: all, history: eight)).first == "quads-compound-2")
    }

    @Test func theUsersOwnLastChoiceIsContinued() throws {
        let other = try candidate("quads-compound-3")
        let plan = WorkoutBuilder.plan(.lowerBody, minutes: 45, from: all, history: [[other.id]])
        #expect(shown(plan).first == "quads-compound-3")
    }

    @Test func extraExercisesVaryFromWorkoutToWorkout() {
        let plans = run(.push, minutes: 60, times: 2).map { plan in
            Set(shown(plan).filter { $0.hasPrefix("chest-isolation") })
        }
        #expect(!plans[0].isEmpty)
        #expect(plans[0].isDisjoint(with: plans[1]))
    }

    @Test func exercisesThatNoLongerExistAreIgnored() {
        let plan = WorkoutBuilder.plan(.fullBody, minutes: 45, from: all, history: [[UUID()], [UUID(), UUID()]])
        #expect(shown(plan).first == "quads-compound-1")
    }

    // MARK: Alternative

    @Test func anAlternativeTrainsTheSameMuscleTheSameWay() throws {
        let squat = try candidate("quads-compound-1")
        #expect(WorkoutBuilder.alternative(to: squat, from: all) == (try candidate("quads-compound-2")))
        #expect(WorkoutBuilder.alternative(to: squat, from: [squat]) == nil)
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
