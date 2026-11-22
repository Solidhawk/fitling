import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// Composing a workout on the real catalogue: the time the user has and main lifts that stay (UNFORGET S28).
@MainActor
@Suite struct WorkoutGeneratorTests {
    let fixture: TrainingFixture
    let profile: UserProfile
    init() throws {
        fixture = try TrainingFixture()
        try fixture.installCatalog()
        profile = fixture.profile(countsWorkouts: false)
    }

    func englishNames(_ plan: WorkoutPlan) -> [String] {
        plan.exercises.compactMap { fixture.store.exercise($0.exerciseID)?.name.values["en"] }
    }

    func viewModel() -> TrainingViewModel {
        TrainingViewModel(
            profile: profile, context: fixture.context, health: FakeHealthReader(),
            defaults: fixture.defaults, timeZone: .gmt, now: { [now = fixture.now] in now }
        )
    }

    @Test func aBeginnerStartsWithTheBasicsOfTheReadyMadeProgrammes() {
        let plan = WorkoutBuilder.plan(.fullBody, minutes: 45, from: fixture.store.workoutCandidates(), history: [])
        #expect(englishNames(plan) == ["Barbell back squat", "Bench press", "Barbell row", "Deadlift", "Overhead press"])
    }

    @Test func candidatesKnowTheirPlaceInTheReadyMadeProgrammes() throws {
        let candidates = fixture.store.workoutCandidates()
        func place(_ english: String) throws -> Int? {
            let id = try fixture.exercise(english).id
            return candidates.first { $0.id == id }?.preference
        }
        let squat = try #require(try place("Barbell back squat")), press = try #require(try place("Leg press"))
        #expect(squat < press)
        #expect(try place("Dumbbell sumo squat") == nil)
    }

    @Test func theHistoryIsNewestFirstAndInTheOrderTheExercisesWereDone() throws {
        let store = fixture.store
        let bench = try fixture.exercise("Bench press"), row = try fixture.exercise("Barbell row")
        let squat = try fixture.exercise("Barbell back squat")
        fixture.workout(squat, daysAgo: 4, sets: [(100, 8, false)])
        let session = store.start(nil)
        store.log(in: session, exercise: squat, weightKg: 40, reps: 10, rpe: nil, isWarmup: true)
        for exercise in [row, bench, row] { store.log(in: session, exercise: exercise, weightKg: 50, reps: 8, rpe: 7, isWarmup: false) }
        #expect(store.workoutHistory() == [[squat.id]], "an unfinished workout does not count")
        store.finish(session)
        #expect(store.workoutHistory() == [[row.id, bench.id], [squat.id]])
    }

    @Test func everyChoiceFitsItsTimeOnTheRealCatalogue() {
        let candidates = fixture.store.workoutCandidates()
        for focus in TrainingFocus.allCases {
            for minutes in WorkoutBuilder.durations {
                var history: [[UUID]] = []
                for _ in 0..<20 {
                    let plan = WorkoutBuilder.plan(focus, minutes: minutes, from: candidates, history: history)
                    #expect(!plan.exercises.isEmpty, "\(focus) \(minutes)")
                    #expect(plan.seconds <= minutes * 60, "\(focus) \(minutes)")
                    history.insert(plan.exercises.map(\.exerciseID), at: 0)
                }
            }
        }
    }

    @Test func theTimeStartsAtAnHourAndIsRemembered() {
        let first = viewModel()
        #expect(first.workoutMinutes == 60)
        first.workoutMinutes = 20
        #expect(viewModel().workoutMinutes == 20)
    }

    @Test func aRememberedTimeThatIsNoLongerAChoiceFallsBackToAnHour() {
        fixture.defaults.set(37, forKey: "fitling.workoutMinutes")
        #expect(viewModel().workoutMinutes == 60)
    }

    @Test func theChosenTimeIsWhatStarts() {
        let model = viewModel()
        model.workoutMinutes = 20
        let plan = model.plan(for: .fullBody)
        #expect(plan.minutes == 20)
        #expect(plan.seconds <= 20 * 60)
        let session = model.startComposed(.fullBody)
        let items = session.programDayID.flatMap { fixture.store.day($0) }.map { fixture.store.items(of: $0) } ?? []
        #expect(items.map(\.exerciseID) == plan.exercises.map(\.exerciseID))
        #expect(items.map(\.targetSets) == plan.exercises.map(\.sets))
        #expect(items.map(\.restSeconds) == plan.exercises.map(\.restSeconds))
    }

    @Test func theMainLiftIsStillThereAfterAWorkout() {
        let model = viewModel()
        let store = model.store
        let first = model.plan(for: .fullBody).exercises
        let session = model.startComposed(.fullBody)
        for planned in first {
            guard let exercise = store.exercise(planned.exerciseID) else { continue }
            store.log(in: session, exercise: exercise, weightKg: 40, reps: 8, rpe: 7, isWarmup: false)
        }
        store.finish(session)
        #expect(model.plan(for: .fullBody).exercises.prefix(5).map(\.exerciseID) == first.prefix(5).map(\.exerciseID))
    }
}
