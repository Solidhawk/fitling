import Foundation
import SwiftData
import Testing
import UIKit
import FitlingCore
@testable import Fitling

@MainActor
struct TrainingFixture {
    let container: ModelContainer
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let defaults: UserDefaults
    var context: ModelContext { container.mainContext }
    var today: Day { Day(now, timeZone: .gmt) }

    init() throws {
        container = try makeModelContainer(inMemory: true)
        let suite = "TrainingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
    }

    var catalog: SportCatalog {
        // The unit tests run inside the app, so the main bundle is the app's.
        get throws { try #require(SportCatalog.bundled()) }
    }

    func installCatalog() throws {
        try catalog.install(into: context, defaults: defaults, now: now)
    }

    var store: TrainingStore {
        TrainingStore(context: context, userID: userID, timeZone: .gmt, now: { [now] in now }, language: "nl")
    }

    func exercise(_ english: String) throws -> Exercise {
        try #require(store.exercises().first { $0.name.values["en"] == english })
    }

    /// A finished workout `daysAgo` with the given sets of one exercise.
    func workout(_ exercise: Exercise, daysAgo: Int, sets: [(Double, Int, Bool)], rpe: Double? = 7) {
        let session = WorkoutSession(
            id: UUID(), userID: userID, programDayID: nil, performedOn: today.adding(-daysAgo),
            startedAt: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)), updatedAt: now
        )
        session.endedAt = session.startedAt.addingTimeInterval(3_600)
        context.insert(session)
        for (index, set) in sets.enumerated() {
            context.insert(WorkoutSet(
                id: UUID(), userID: userID, sessionID: session.id, exerciseID: exercise.id, position: index,
                weightKg: set.0, reps: set.1, rpe: set.2 ? nil : rpe, isWarmup: set.2, updatedAt: now
            ))
        }
        try? context.save()
    }

    func profile(countsWorkouts: Bool) -> UserProfile {
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        let profile = UserProfile(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body,
            targets: NutritionTargets(kcal: 2500, proteinG: 128, carbsG: 300, fatG: 80), targetsAreManual: false, updatedAt: now
        )
        profile.countsWorkoutEnergy = countsWorkouts
        context.insert(profile)
        try? context.save()
        return profile
    }
}

// MARK: - 4.1 en 4.2 Oefeningen, schema's en sync

@MainActor
@Suite struct SportCatalogTests {
    let fixture: TrainingFixture
    init() throws { fixture = try TrainingFixture() }

    @Test func catalogInstallsTheSharedRows() throws {
        try fixture.installCatalog()
        let catalog = try fixture.catalog
        #expect(fixture.store.exercises().count == catalog.exercises.count)
        #expect(fixture.store.programs().map(\.daysPerWeek) == [3, 4, 6])
        let pending = try fixture.context.fetchCount(Exercise.pending) + fixture.context.fetchCount(Program.pending)
            + fixture.context.fetchCount(ProgramDay.pending) + fixture.context.fetchCount(ProgramExercise.pending)
        #expect(pending == 0)
    }

    @Test func installingTwiceAddsNothing() throws {
        try fixture.installCatalog()
        try fixture.installCatalog()
        fixture.defaults.removeObject(forKey: "fitling.sportCatalogVersion")
        try fixture.installCatalog()
        #expect(try fixture.context.fetchCount(FetchDescriptor<Exercise>()) == fixture.catalog.exercises.count)
    }

    @Test func aCatalogErasedBySigningOutComesBack() throws {
        try fixture.installCatalog()
        for exercise in try fixture.context.fetch(FetchDescriptor<Exercise>()) { fixture.context.delete(exercise) }
        try fixture.context.save()
        try fixture.installCatalog()
        #expect(try fixture.context.fetchCount(FetchDescriptor<Exercise>()) == fixture.catalog.exercises.count)
    }

    @Test func copyingAProgramMakesItYours() throws {
        try fixture.installCatalog()
        let shared = try #require(fixture.store.programs().first)
        let copy = fixture.store.copy(shared, named: "Mijn schema")

        #expect(copy.ownerID == fixture.userID)
        #expect(copy.needsPush)
        let days = fixture.store.days(of: copy)
        #expect(days.count == fixture.store.days(of: shared).count)
        #expect(days.allSatisfy { $0.ownerID == fixture.userID && $0.needsPush })
        #expect(fixture.store.items(of: days[0]).map(\.exerciseID) == fixture.store.items(of: fixture.store.days(of: shared)[0]).map(\.exerciseID))
        // The shared original never becomes the user's.
        #expect(shared.ownerID == nil)
        #expect(!shared.needsPush)
    }

    @Test func sharedProgramsCannotBeChanged() throws {
        try fixture.installCatalog()
        let shared = try #require(fixture.store.programs().first)
        let day = try #require(fixture.store.days(of: shared).first)
        let before = fixture.store.items(of: day).count
        #expect(fixture.store.add(try fixture.exercise("Push-up"), to: day, sets: 3, repRange: 8...12, restSeconds: 90) == nil)
        fixture.store.delete(shared)
        #expect(fixture.store.items(of: day).count == before)
        #expect(shared.deletedAt == nil)
    }

    /// Drawings come as a start and an end. Everkinetic has no drawing of the movements listed here
    /// (UNFORGET S19); those show a symbol instead.
    @Test func everyExerciseHasBothDrawingsExceptTheKnownOnes() throws {
        let catalog = try fixture.catalog
        func drawing(_ id: UUID, _ phase: String) -> Bool {
            UIImage(named: "Exercises/\(id.uuidString.lowercased())-\(phase)") != nil
        }
        for entry in catalog.exercises {
            #expect(drawing(entry.id, "start") == drawing(entry.id, "end"), "\(entry.name.values["en"] ?? "")")
        }
        let without = catalog.exercises.filter { !ExerciseDrawing.exists(for: $0.id) }.compactMap { $0.name.values["en"] }.sorted()
        #expect(without == ["Cable crunch", "Face pull", "Goblet squat", "Hanging leg raise", "Hip thrust", "Kettlebell swing", "One-arm dumbbell row"])
    }

    @Test func sportRecordsKeepEveryColumn() throws {
        try fixture.installCatalog()
        let exercise = try fixture.exercise("Bench press")
        let session = fixture.store.start(nil)
        let set = fixture.store.log(in: session, exercise: exercise, weightKg: 62.5, reps: 8, rpe: 8.5, isWarmup: false)

        let decodedSet = try JSONDecoder().decode(WorkoutSetRecord.self, from: JSONEncoder().encode(set.record))
        #expect(decodedSet == set.record)
        let decodedExercise = try JSONDecoder().decode(ExerciseRecord.self, from: JSONEncoder().encode(exercise.record))
        #expect(decodedExercise == exercise.record)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.record)) as? [String: Any]
        #expect(json?["synced_at"] == nil)
        #expect(json?.keys.contains("ended_at") == true)
    }
}

// MARK: - 4.4 Training loggen

@MainActor
@Suite struct WorkoutTests {
    let fixture: TrainingFixture
    init() throws {
        fixture = try TrainingFixture()
        try fixture.installCatalog()
    }

    func workout(day position: Int = 0, unit: WeightUnit = .kilograms) throws -> WorkoutViewModel {
        let program = try #require(fixture.store.programs().first)
        let day = fixture.store.days(of: program)[position]
        return WorkoutViewModel(session: fixture.store.start(day), store: fixture.store, unit: unit)
    }

    @Test func aWorkoutListsTheExercisesOfItsDay() throws {
        let workout = try workout()
        let program = try #require(fixture.store.programs().first)
        #expect(workout.entries.map(\.exercise.id) == fixture.store.items(of: fixture.store.days(of: program)[0]).map(\.exerciseID))
    }

    @Test func finishingSetsEndedAt() throws {
        let workout = try workout()
        #expect(fixture.store.activeSession()?.id == workout.session.id)
        workout.finish()
        #expect(workout.session.endedAt == fixture.now)
        #expect(workout.session.needsPush)
        #expect(fixture.store.activeSession() == nil)
    }

    @Test func restTimerStartsAfterASet() throws {
        let workout = try workout()
        let entry = try #require(workout.entries.first)
        workout.drafts[entry.id] = .init(weight: 60, reps: 8, isWarmup: true)
        workout.log(entry)
        #expect(workout.restEndsAt == nil)

        workout.drafts[entry.id] = .init(weight: 80, reps: 8)
        workout.log(entry)
        let rest = try #require(entry.item?.restSeconds)
        #expect(workout.restEndsAt == fixture.now.addingTimeInterval(TimeInterval(rest)))
        #expect(workout.sets(of: entry).count == 2)
    }

    @Test func weightIsStoredInKilograms() throws {
        let workout = try workout(unit: .pounds)
        let entry = try #require(workout.entries.first)
        workout.drafts[entry.id] = .init(weight: 135, reps: 5)
        let set = try #require(workout.log(entry))
        #expect(set.weightKg == 61.23)
        #expect(WeightUnit.pounds.format(kilograms: set.weightKg).hasSuffix(UnitMass.pounds.symbol))
    }

    @Test func aSetNeedsWeightAndReps() throws {
        let workout = try workout()
        let entry = try #require(workout.entries.first)
        workout.drafts[entry.id] = .init(weight: 60, reps: nil)
        #expect(!workout.canLog(entry))
        #expect(workout.log(entry) == nil)
    }

    @Test func discardingRemovesTheSets() throws {
        let workout = try workout()
        let entry = try #require(workout.entries.first)
        workout.drafts[entry.id] = .init(weight: 60, reps: 8)
        let set = try #require(workout.log(entry))
        workout.discard()
        #expect(workout.session.deletedAt != nil)
        #expect(set.deletedAt != nil)
        #expect(fixture.store.activeSession() == nil)
    }

    @Test func theNextWorkoutFollowsTheLastOne() throws {
        let first = try workout(day: 0)
        first.finish()
        // The second workout of the test starts later than the first.
        first.session.startedAt = fixture.now.addingTimeInterval(-86_400)
        let next = try #require(fixture.store.nextDay())
        #expect(next.day.position == 1)

        let program = try #require(fixture.store.programs().first)
        let last = WorkoutViewModel(session: fixture.store.start(fixture.store.days(of: program).last), store: fixture.store, unit: .kilograms)
        last.finish()
        #expect(fixture.store.nextDay()?.day.position == 0)
    }
}

// MARK: - 4.5 Progressie-advies

@MainActor
@Suite struct ProgressionAdviceTests {
    let fixture: TrainingFixture
    init() throws {
        fixture = try TrainingFixture()
        try fixture.installCatalog()
    }

    @Test func adviceUsesTheUsersOwnStep() throws {
        let squat = try fixture.exercise("Barbell back squat")
        fixture.workout(squat, daysAgo: 3, sets: [(100, 8, false), (100, 8, false), (100, 8, false)])
        let rules = ExerciseRules(kind: .compound, repRange: 6...8, targetSets: 3, stepKg: squat.defaultStepKg)
        #expect(ProgressionEngine.advise(history: fixture.store.history(of: squat.id), rules: rules, today: fixture.today) == .increase(toKg: 102.5))

        fixture.store.saveStep(5, for: squat)
        let program = try #require(fixture.store.programs().first)
        let item = try #require(fixture.store.days(of: program).flatMap { fixture.store.items(of: $0) }.first { $0.exerciseID == squat.id })
        #expect(fixture.store.advice(for: squat, in: item) == .increase(toKg: 105))
    }

    @Test func warmUpSetsAreIgnored() throws {
        let squat = try fixture.exercise("Barbell back squat")
        fixture.workout(squat, daysAgo: 3, sets: [(40, 10, true), (60, 5, true), (100, 6, false), (100, 6, false), (100, 6, false)])
        let history = fixture.store.history(of: squat.id)
        #expect(history.count == 1)
        #expect(history[0].sets.allSatisfy { $0.weightKg == 100 })
        #expect(history[0].sets.count == 3)
    }

    @Test func acceptingAdvicePrefillsTheNextSet() throws {
        let program = try #require(fixture.store.programs().first)
        let day = try #require(fixture.store.days(of: program).first)
        let item = try #require(fixture.store.items(of: day).first)
        let exercise = try #require(fixture.store.exercise(item.exerciseID))
        let sets = Array(repeating: (100.0, item.repMax, false), count: item.targetSets)
        fixture.workout(exercise, daysAgo: 3, sets: sets)

        let workout = WorkoutViewModel(session: fixture.store.start(day), store: fixture.store, unit: .kilograms)
        let entry = try #require(workout.entries.first { $0.id == item.id })
        guard case let .increase(weight) = workout.advice(for: entry) else {
            Issue.record("expected an increase, got \(workout.advice(for: entry))")
            return
        }
        #expect(workout.drafts[entry.id]?.weight == weight)
        #expect(workout.drafts[entry.id]?.reps == item.repMin)
    }

    @Test func keepGoingAimsForOneMoreRep() throws {
        let program = try #require(fixture.store.programs().first)
        let day = try #require(fixture.store.days(of: program).first)
        let item = try #require(fixture.store.items(of: day).first)
        let exercise = try #require(fixture.store.exercise(item.exerciseID))
        fixture.workout(exercise, daysAgo: 3, sets: [(100, item.repMin, false), (100, item.repMin, false), (100, item.repMin, false)])

        let workout = WorkoutViewModel(session: fixture.store.start(day), store: fixture.store, unit: .kilograms)
        let entry = try #require(workout.entries.first { $0.id == item.id })
        #expect(workout.advice(for: entry) == .keepGoing(weightKg: 100))
        #expect(workout.drafts[entry.id]?.reps == item.repMin + 1)
    }

    @Test func recordsOfTheWorkoutAreFound() throws {
        let squat = try fixture.exercise("Barbell back squat")
        fixture.workout(squat, daysAgo: 3, sets: [(100, 6, false)])
        let workout = WorkoutViewModel(session: fixture.store.start(nil), store: fixture.store, unit: .kilograms)
        workout.add(squat)
        let entry = try #require(workout.entries.first)
        workout.drafts[entry.id] = .init(weight: 105, reps: 6)
        workout.log(entry)
        #expect(workout.records().contains { $0.1 == .weight(kg: 105) })
    }
}

// MARK: - 4.7 HealthKit

@MainActor
@Suite struct HealthImportTests {
    let fixture: TrainingFixture
    init() throws { fixture = try TrainingFixture() }

    @Test func storesWorkoutEnergyPerDay() async throws {
        let reader = FakeHealthReader()
        reader.energy = [fixture.today: 250.4, fixture.today.adding(-1): 400]
        let importer = HealthImport(context: fixture.context, reader: reader, timeZone: .gmt, now: { [now = fixture.now] in now })

        await importer.run()
        await importer.run()

        let activities = try fixture.context.fetch(FetchDescriptor<DayActivity>(sortBy: [SortDescriptor(\.day)]))
        #expect(activities.map(\.day) == [fixture.today.adding(-1).isoString, fixture.today.isoString])
        #expect(activities.map(\.workoutKcal) == [400, 250])
    }

    @Test func budgetGrowsOnlyWhenTheSwitchIsOn() throws {
        fixture.context.insert(DayActivity(day: fixture.today, workoutKcal: 400, updatedAt: fixture.now))
        let off = fixture.profile(countsWorkouts: false)
        let without = fixture.context.targets(on: fixture.today, for: off).kcal
        off.countsWorkoutEnergy = true
        let with = fixture.context.targets(on: fixture.today, for: off).kcal
        #expect(without == 2500)
        #expect(with > without)
    }

    @Test func turningItOnAsksForAccessFirst() async throws {
        let reader = FakeHealthReader()
        reader.grantsAccess = false
        let profile = fixture.profile(countsWorkouts: false)
        let training = TrainingViewModel(profile: profile, context: fixture.context, health: reader, timeZone: .gmt, now: { [now = fixture.now] in now })

        await training.setCountsWorkoutEnergy(true)
        #expect(!profile.countsWorkoutEnergy)
        #expect(training.healthRefused)

        reader.grantsAccess = true
        reader.energy = [fixture.today: 300]
        await training.setCountsWorkoutEnergy(true)
        #expect(profile.countsWorkoutEnergy)
        #expect(profile.needsPush)
        #expect(try fixture.context.fetchCount(FetchDescriptor<DayActivity>()) == 1)
    }
}

// MARK: - 4.8 en 4.9 Lichaam en foto's

@MainActor
@Suite struct BodyTests {
    let fixture: TrainingFixture
    init() throws { fixture = try TrainingFixture() }

    @Test func imperialInputIsStoredInKilogramsAndCentimetres() throws {
        let log = BodyLog(context: fixture.context, userID: fixture.userID, usesMetric: false, timeZone: .gmt, now: { [now = fixture.now] in now })
        let weight = try #require(log.add(176, kind: .weight, on: fixture.today))
        let waist = try #require(log.add(32, kind: .waist, on: fixture.today))
        #expect(weight.value == 79.8)
        #expect(waist.value == 81.3)
        #expect(abs(log.displayValue(weight) - 176) < 0.2)
    }

    @Test func impossibleValuesAndFutureDaysAreRefused() {
        let log = BodyLog(context: fixture.context, userID: fixture.userID, usesMetric: true, timeZone: .gmt, now: { [now = fixture.now] in now })
        #expect(log.add(0, kind: .weight, on: fixture.today) == nil)
        #expect(log.add(600, kind: .waist, on: fixture.today) == nil)
        #expect(log.add(80, kind: .weight, on: fixture.today.adding(1)) == nil)
        #expect(log.add(80, kind: .weight, on: fixture.today) != nil)
        #expect(log.measurements(of: .weight).count == 1)
    }

    @Test func photosStayOutOfBackupsAndGoOnSignOut() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "photos-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = ProgressPhotoStore(context: fixture.context, folder: folder, timeZone: .gmt, now: { [now = fixture.now] in now })
        let photo = try store.add(Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let values = try store.url(of: photo).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(store.photos().count == 1)

        store.removeAll()
        #expect(!FileManager.default.fileExists(atPath: folder.path()))
    }
}

// MARK: - Coach (feedback 2026-11-21: compose a workout, go heavier, switch exercises)

@MainActor
@Suite struct TrainingCoachTests {
    let fixture: TrainingFixture
    init() throws {
        fixture = try TrainingFixture()
        try fixture.installCatalog()
    }

    @Test func aComposedWorkoutBecomesTheDayOfOneOwnProgramme() {
        let store = fixture.store
        let upper = WorkoutBuilder.build(.upperBody, from: store.workoutCandidates())
        #expect(!upper.isEmpty)
        let day = store.compose(upper, into: nil, programName: "Samengesteld", dayName: "Bovenlichaam")
        #expect(store.items(of: day).map(\.exerciseID) == upper.map(\.exerciseID))

        let lower = WorkoutBuilder.build(.lowerBody, from: store.workoutCandidates())
        let again = store.compose(lower, into: day.programID, programName: "Samengesteld", dayName: "Onderlichaam")
        #expect(again.id == day.id)
        #expect(store.items(of: again).map(\.exerciseID) == lower.map(\.exerciseID))
        #expect(store.programs().filter { $0.ownerID == fixture.userID }.count == 1)
        #expect(again.name.values["nl"] == "Onderlichaam")
    }

    @Test func candidatesKnowWhenEachExerciseWasLastDone() throws {
        let bench = try fixture.exercise("Bench press")
        fixture.workout(bench, daysAgo: 9, sets: [(60, 10, false)])
        fixture.workout(bench, daysAgo: 2, sets: [(60, 10, false)])
        let candidate = try #require(fixture.store.workoutCandidates().first { $0.id == bench.id })
        #expect(candidate.lastDone == fixture.today.adding(-2))
    }

    @Test func theCoachSaysWhatCanGoHeavierAndWhatHasStalled() throws {
        let bench = try fixture.exercise("Bench press")
        fixture.workout(bench, daysAgo: 2, sets: [(60, 12, false), (60, 12, false), (60, 12, false)])
        let squat = try fixture.exercise("Barbell back squat")
        fixture.workout(squat, daysAgo: 20, sets: [(100, 8, false)])
        for daysAgo in [16, 12, 8, 4] {
            fixture.workout(squat, daysAgo: daysAgo, sets: [(100, 7, false)])
        }

        let notes = fixture.store.coachNotes()
        let benchNote = try #require(notes.first { $0.exercise.id == bench.id })
        #expect(benchNote.kind == .heavier(.increase(toKg: 62.5)))
        let squatNote = try #require(notes.first { $0.exercise.id == squat.id })
        guard case let .switchTo(other) = squatNote.kind else {
            Issue.record("expected a switch for the squat")
            return
        }
        #expect(other.id != squat.id)
    }

    /// Exercises done on the same day come in alphabetical order, so the list does not reshuffle
    /// every time the screen loads (it did: the order came from a dictionary).
    @Test func notesFromTheSameDayComeInAlphabeticalOrder() throws {
        let names = ["Bench press", "Overhead press", "Barbell row", "Lateral raise", "Dumbbell curl", "Leg extension"]
        for name in names {
            fixture.workout(try fixture.exercise(name), daysAgo: 2, sets: [(20, 12, false), (20, 12, false), (20, 12, false)])
        }
        let shown = fixture.store.coachNotes(limit: names.count).map { $0.exercise.name.text(preferring: ["nl"]) }
        #expect(shown.count == names.count)
        #expect(shown == shown.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    /// The made-up workouts the UI test starts with must give the coach a note of each kind, or
    /// the screenshot of the coach shows nothing.
    @Test func theUITestWorkoutsGiveTheCoachANoteOfEachKind() {
        UITestEnvironment.insertWorkoutHistory(userID: fixture.userID, into: fixture.context, defaults: fixture.defaults, now: fixture.now, timeZone: .gmt)
        let notes = fixture.store.coachNotes()
        #expect(notes.contains { if case .heavier = $0.kind { true } else { false } })
        #expect(notes.contains { if case .switchTo = $0.kind { true } else { false } })
        #expect(fixture.store.finishedSessions(limit: 10).allSatisfy { $0.userID == fixture.userID && $0.endedAt != nil })
    }
}
