import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// A composed workout no longer overwrites the one before it (UNFORGET S30).
@MainActor
@Suite struct ComposedTrainingTests {
    let fixture: TrainingFixture
    let profile: UserProfile
    let bench: Exercise
    let squat: Exercise

    init() throws {
        fixture = try TrainingFixture()
        try fixture.installCatalog()
        profile = fixture.profile(countsWorkouts: false)
        bench = try fixture.exercise("Bench press")
        squat = try fixture.exercise("Barbell back squat")
    }

    /// The store as it was so many days ago: workouts need their own start to have an order.
    func store(daysAgo: Int) -> TrainingStore {
        let then = fixture.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        return TrainingStore(context: fixture.context, userID: fixture.userID, timeZone: .gmt, now: { then }, language: "nl")
    }

    func viewModel(defaults: UserDefaults? = nil) -> TrainingViewModel {
        TrainingViewModel(
            profile: profile, context: fixture.context, health: FakeHealthReader(),
            defaults: defaults ?? fixture.defaults, timeZone: .gmt, now: { [now = fixture.now] in now }
        )
    }

    @discardableResult
    func composed(_ focus: TrainingFocus, _ name: String, sets: Int = 3, daysAgo: Int) -> ProgramDay {
        let exercise = focus == .lowerBody ? squat : bench
        return store(daysAgo: daysAgo).compose(
            [PlannedExercise(exerciseID: exercise.id, sets: sets, repRange: 6...10, restSeconds: 150)],
            for: focus, programName: "Samengesteld", dayName: name
        )
    }

    @discardableResult
    func done(_ focus: TrainingFocus, _ name: String, sets: Int = 3, logged: Int = 3, daysAgo: Int) -> WorkoutSession {
        let day = composed(focus, name, sets: sets, daysAgo: daysAgo)
        let store = store(daysAgo: daysAgo)
        let session = store.start(day)
        let exercise = focus == .lowerBody ? squat : bench
        for _ in 0..<logged { store.log(in: session, exercise: exercise, weightKg: 60, reps: 10, rpe: 7, isWarmup: false) }
        store.finish(session)
        return session
    }

    var composedPrograms: [Program] {
        fixture.store.programs().filter { $0.ownerID == fixture.userID }
    }

    @Test func anEarlierWorkoutKeepsItsName() {
        let monday = done(.upperBody, "Bovenlichaam", daysAgo: 2)
        let wednesday = done(.lowerBody, "Onderlichaam", daysAgo: 0)
        let model = viewModel()
        #expect(model.title(of: monday)?.values["nl"] == "Bovenlichaam")
        #expect(model.title(of: wednesday)?.values["nl"] == "Onderlichaam")
    }

    @Test func composingAgainLeavesTheDoneWorkoutsExercisesAlone() throws {
        let session = done(.upperBody, "Bovenlichaam", daysAgo: 2)
        composed(.lowerBody, "Onderlichaam", daysAgo: 0)
        let day = try #require(session.programDayID.flatMap { fixture.store.day($0) })
        #expect(fixture.store.items(of: day).map(\.exerciseID) == [bench.id])
    }

    @Test func theDayKnowsItsFocus() {
        #expect(ComposedWorkout.focus(of: composed(.pull, "Trekken", daysAgo: 0).id) == .pull)
    }

    @Test func afterAComposedWorkoutTheNextOneIsComposedForTheFocusWhoseTurnItIs() {
        done(.upperBody, "Bovenlichaam", daysAgo: 4)
        done(.lowerBody, "Onderlichaam", daysAgo: 2)
        guard case let .compose(focus) = fixture.store.nextWorkout() else {
            Issue.record("the next workout repeats the last one")
            return
        }
        #expect(focus == .upperBody)
    }

    @Test func afterAWorkoutFromAProgrammeTheProgrammeGoesOn() throws {
        done(.upperBody, "Bovenlichaam", daysAgo: 4)
        let program = try #require(fixture.store.programs().first)
        let store = store(daysAgo: 1)
        store.finish(store.start(store.days(of: program).first))
        guard case let .programDay(_, day) = fixture.store.nextWorkout() else {
            Issue.record("expected the programme")
            return
        }
        #expect(day.position == 1)
    }

    /// The programme used to be found through a key on the device, or else by its name.
    @Test func anotherDeviceAndARenamedProgrammeStillGiveOneProgramme() throws {
        done(.upperBody, "Bovenlichaam", daysAgo: 2)
        let program = try #require(composedPrograms.first)
        fixture.store.rename(program, to: "Mijn trainingen")
        let otherDevice = try #require(UserDefaults(suiteName: "ComposedTrainingTests.\(UUID().uuidString)"))
        _ = viewModel(defaults: otherDevice).startComposed(.lowerBody)
        #expect(composedPrograms.count == 1)
        #expect(program.name.values["nl"] == "Mijn trainingen")
    }

    @Test func anOwnProgrammeWithTheSameNameIsLeftAlone() {
        let own = fixture.store.createProgram(named: "Samengesteld", daysPerWeek: 2) { "Dag \($0)" }
        composed(.upperBody, "Bovenlichaam", daysAgo: 0)
        #expect(fixture.store.days(of: own).map { $0.name.values["nl"] } == ["Dag 1", "Dag 2"])
        #expect(composedPrograms.count == 2)
    }

    @Test func aDeletedProgrammeMakesRoomForANewOneAndTheOldWorkoutKeepsItsName() throws {
        let old = done(.upperBody, "Bovenlichaam", daysAgo: 2)
        let program = try #require(composedPrograms.first)
        fixture.store.delete(program)
        let day = composed(.lowerBody, "Onderlichaam", daysAgo: 0)
        #expect(day.programID != program.id)
        #expect(viewModel().title(of: old)?.values["nl"] == "Bovenlichaam")
    }

    @Test func discardingTakesItsDayWithIt() {
        let day = composed(.upperBody, "Bovenlichaam", daysAgo: 0)
        let items = fixture.store.items(of: day)
        fixture.store.discard(fixture.store.start(day))
        #expect(day.deletedAt != nil)
        #expect(day.needsPush)
        #expect(items.allSatisfy { $0.deletedAt != nil })
    }

    @Test func discardingARepeatKeepsTheDayOfTheWorkoutThatWasDone() throws {
        let finished = done(.upperBody, "Bovenlichaam", daysAgo: 2)
        let day = try #require(finished.programDayID.flatMap { fixture.store.day($0) })
        fixture.store.discard(fixture.store.start(day))
        #expect(day.deletedAt == nil)
        #expect(!fixture.store.items(of: day).isEmpty)
    }

    @Test func discardingAWorkoutFromTheUsersOwnProgrammeKeepsTheDay() throws {
        let own = fixture.store.createProgram(named: "Eigen", daysPerWeek: 1) { "Dag \($0)" }
        let day = try #require(fixture.store.days(of: own).first)
        fixture.store.discard(fixture.store.start(day))
        #expect(day.deletedAt == nil)
    }

    @Test func startingWhileAWorkoutRunsMakesNoExtraDay() throws {
        let model = viewModel()
        let first = model.startComposed(.upperBody)
        let second = model.startComposed(.lowerBody)
        #expect(second.id == first.id)
        let day = try #require(first.programDayID.flatMap { fixture.store.day($0) })
        #expect(day.name.values[model.store.language] == String(localized: TrainingFocus.upperBody.titleResource))
        let program = try #require(composedPrograms.first)
        #expect(fixture.store.days(of: program).count == 1)
    }

    @Test func theProgrammeShowsTheTenNewestFirst() throws {
        for number in 1...12 { composed(.upperBody, "Training \(number)", daysAgo: 12 - number) }
        let program = try #require(composedPrograms.first)
        let shown = fixture.store.daysToShow(of: program).compactMap { $0.name.values["nl"] }
        #expect(shown == stride(from: 12, through: 3, by: -1).map { "Training \($0)" })
    }

    @Test func anOtherProgrammeShowsEveryDayInItsOwnOrder() throws {
        let program = try #require(fixture.store.programs().last { $0.ownerID == nil })
        #expect(fixture.store.daysToShow(of: program).map(\.id) == fixture.store.days(of: program).map(\.id))
    }

    /// With the day refilled the coach had to guess the target from the sets done: two of three counted as all.
    @Test func theCoachUsesTheSetsThatWerePlanned() {
        done(.upperBody, "Bovenlichaam", sets: 3, logged: 2, daysAgo: 2)
        composed(.lowerBody, "Onderlichaam", daysAgo: 0)
        #expect(fixture.store.adviceAfterLastWorkout(for: bench) == .keepGoing(weightKg: 60))
    }
}
