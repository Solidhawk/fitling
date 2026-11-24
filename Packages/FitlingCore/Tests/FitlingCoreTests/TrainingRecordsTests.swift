import Foundation
import Testing
@testable import FitlingCore

/// The training rules the app and the web share (web phase 4); TrainingTests and ComposedTrainingTests in the app
/// check the same through TrainingStore.
@Suite struct TrainingRecordsTests {
    let user = UUID()
    let today = Day(isoString: "2026-11-18")!
    /// 2026-11-18, 11:06 UTC.
    let now = 1_795_000_000.0

    func exercise(_ name: String, kind: String = "compound", muscles: [String] = ["chest"], step: Double = 2.5) -> ExerciseRecord {
        ExerciseRecord(
            id: UUID(), ownerID: nil, name: LocalizedText(["en": name, "nl": name]), kind: kind, loadType: "external",
            primaryMuscles: muscles, secondaryMuscles: [], defaultStepKg: step
        )
    }

    /// A finished workout `daysAgo` with sets of one exercise: weight, reps, warm-up.
    func workout(
        _ exercise: ExerciseRecord, daysAgo: Int, sets: [(Double, Int, Bool)], day: UUID? = nil, startOffset: Double = 0, rpe: Double = 7
    ) -> (SessionRecord, [SetRecord]) {
        let session = SessionRecord(
            id: UUID(), programDayID: day, performedOn: today.adding(-daysAgo), startedAt: now - Double(daysAgo * 86_400) + startOffset,
            endedAt: now - Double(daysAgo * 86_400) + startOffset + 3_600
        )
        let records = sets.enumerated().map { index, set in
            SetRecord(id: UUID(), sessionID: session.id, exerciseID: exercise.id, position: index, weightKg: set.0, reps: set.1, rpe: set.2 ? nil : rpe, isWarmup: set.2)
        }
        return (session, records)
    }

    func book(
        exercises: [ExerciseRecord], programs: [ProgramRecord] = [], days: [ProgramDayRecord] = [], items: [ProgramItemRecord] = [],
        settings: [ExerciseSettingRecord] = [], workouts: [(SessionRecord, [SetRecord])] = []
    ) -> TrainingRecords {
        TrainingRecords(
            userID: user, exercises: exercises, programs: programs, days: days, items: items, settings: settings,
            sessions: workouts.map(\.0), sets: workouts.flatMap(\.1), today: today, languages: ["nl"]
        )
    }

    /// A shared programme of `count` days with one exercise each: 3 sets of 6–8, 150 s rest.
    func programme(_ exercise: ExerciseRecord, days count: Int, owner: UUID? = nil) -> (ProgramRecord, [ProgramDayRecord], [ProgramItemRecord]) {
        let program = ProgramRecord(id: UUID(), ownerID: owner, name: LocalizedText(["nl": "Schema"]), daysPerWeek: count)
        let days = (0..<count).map { ProgramDayRecord(id: UUID(), programID: program.id, ownerID: owner, name: LocalizedText(["nl": "Dag \($0 + 1)"]), position: $0, updatedAt: now) }
        let items = days.map {
            ProgramItemRecord(id: UUID(), programDayID: $0.id, ownerID: owner, exerciseID: exercise.id, position: 0, targetSets: 3, repMin: 6, repMax: 8, restSeconds: 150)
        }
        return (program, days, items)
    }

    @Test func theNextWorkoutFollowsTheLastOne() {
        let squat = exercise("Squat", muscles: ["quads"])
        let (program, days, items) = programme(squat, days: 3)
        var workouts = [workout(squat, daysAgo: 2, sets: [(100, 8, false)], day: days[0].id)]
        #expect(book(exercises: [squat], programs: [program], days: days, items: items, workouts: workouts).nextWorkout()
            == .programDay(programID: program.id, dayID: days[1].id))
        workouts.append(workout(squat, daysAgo: 1, sets: [(100, 8, false)], day: days[2].id))
        #expect(book(exercises: [squat], programs: [program], days: days, items: items, workouts: workouts).nextWorkout()
            == .programDay(programID: program.id, dayID: days[0].id))
    }

    @Test func afterAComposedWorkoutTheNextFocusIsComposed() {
        let bench = exercise("Bench press")
        let program = ProgramRecord(id: UUID(), ownerID: user, name: LocalizedText(["nl": "Samengesteld"]), daysPerWeek: 1)
        let upper = ProgramDayRecord(id: ComposedWorkout.dayID(for: .upperBody), programID: program.id, ownerID: user, name: LocalizedText(["nl": "Boven"]), position: 0, updatedAt: now)
        let lower = ProgramDayRecord(id: ComposedWorkout.dayID(for: .lowerBody), programID: program.id, ownerID: user, name: LocalizedText(["nl": "Onder"]), position: 1, updatedAt: now)
        let workouts = [
            workout(bench, daysAgo: 3, sets: [(60, 10, false)], day: lower.id),
            workout(bench, daysAgo: 1, sets: [(60, 10, false)], day: upper.id),
        ]
        // Of the focuses in the round, the one done the longest ago.
        #expect(book(exercises: [bench], programs: [program], days: [upper, lower], workouts: workouts).nextWorkout() == .compose(.lowerBody))
    }

    @Test func historyIgnoresWarmUpsAndOrdersByDayThenStart() {
        let squat = exercise("Squat", muscles: ["quads"])
        let later = workout(squat, daysAgo: 3, sets: [(110, 5, false)], startOffset: 7_200)
        let earlier = workout(squat, daysAgo: 3, sets: [(40, 10, true), (100, 6, false), (100, 6, false)])
        let before = workout(squat, daysAgo: 5, sets: [(95, 6, false)])
        let records = book(exercises: [squat], workouts: [later, earlier, before])
        let history = records.history(of: squat.id)
        #expect(history.map { $0.sets.map(\.weightKg) } == [[95], [100, 100], [110]])
        #expect(records.history(of: squat.id, excluding: later.0.id).count == 2)
    }

    @Test func rulesPreferTheUsersSettingThenTheProgramme() {
        let squat = exercise("Squat", muscles: ["quads"])
        let (_, _, items) = programme(squat, days: 1)
        let plain = book(exercises: [squat])
        #expect(plain.rules(for: squat, in: nil) == ExerciseRules(kind: .compound, repRange: 8...12, targetSets: 3, stepKg: 2.5))
        #expect(plain.rules(for: squat, in: items[0]) == ExerciseRules(kind: .compound, repRange: 6...8, targetSets: 3, stepKg: 2.5))
        let settings = [
            ExerciseSettingRecord(exerciseID: squat.id, stepKg: 2, updatedAt: now - 100),
            ExerciseSettingRecord(exerciseID: squat.id, stepKg: 5, repMin: 10, repMax: 12, updatedAt: now),
        ]
        #expect(book(exercises: [squat], settings: settings).rules(for: squat, in: items[0])
            == ExerciseRules(kind: .compound, repRange: 10...12, targetSets: 3, stepKg: 5))
    }

    @Test func keepGoingAimsForOneMoreRep() {
        let squat = exercise("Squat", muscles: ["quads"])
        let (_, _, items) = programme(squat, days: 1)
        let atBottom = book(exercises: [squat], workouts: [workout(squat, daysAgo: 3, sets: [(100, 6, false), (100, 6, false), (100, 6, false)])])
        #expect(atBottom.advice(for: squat, in: items[0]) == .keepGoing(weightKg: 100))
        #expect(atBottom.prefill(squat, in: items[0]) == SetDraft(weightKg: 100, reps: 7))
        let atTop = book(exercises: [squat], workouts: [workout(squat, daysAgo: 3, sets: [(100, 8, false), (100, 8, false), (100, 8, false)])])
        #expect(atTop.prefill(squat, in: items[0]) == SetDraft(weightKg: 102.5, reps: 6))
        #expect(book(exercises: [squat]).prefill(squat, in: items[0]) == SetDraft(weightKg: nil, reps: 6))
    }

    @Test func loggedSetsAreBounded() {
        let set = TrainingRecords.loggedSet(weightKg: 61.234567, reps: 1_200, rpe: 7.3)
        #expect(set.weightKg == 61.23 && set.reps == 1_000 && set.rpe == 7.5)
        let low = TrainingRecords.loggedSet(weightKg: -5, reps: -1, rpe: 0.2)
        #expect(low.weightKg == 0 && low.reps == 0 && low.rpe == 1)
        #expect(TrainingRecords.loggedSet(weightKg: 20, reps: 5, rpe: nil).rpe == nil)
    }

    @Test func theCoachSaysWhatCanGoHeavierAndWhatHasStalled() throws {
        let bench = exercise("Bench press")
        let squat = exercise("Barbell back squat", muscles: ["quads"])
        let legPress = exercise("Leg press", muscles: ["quads"])
        var workouts = [workout(bench, daysAgo: 2, sets: [(60, 12, false), (60, 12, false), (60, 12, false)])]
        workouts.append(workout(squat, daysAgo: 20, sets: [(100, 8, false)]))
        for daysAgo in [16, 12, 8, 4] {
            workouts.append(workout(squat, daysAgo: daysAgo, sets: [(100, 7, false)]))
        }
        let notes = book(exercises: [bench, squat, legPress], workouts: workouts).coachNotes()
        #expect(notes.first { $0.exerciseID == bench.id }?.kind == .heavier(.increase(toKg: 62.5)))
        #expect(notes.first { $0.exerciseID == squat.id }?.kind == .switchTo(legPress.id))
        // Most recent first.
        #expect(notes.map(\.exerciseID) == [bench.id, squat.id])
    }

    @Test func composedDaysShowNewestFirstAndAtMostTen() {
        let bench = exercise("Bench press")
        let own = ProgramRecord(id: UUID(), ownerID: user, name: LocalizedText(["nl": "Samengesteld"]), daysPerWeek: 1)
        let composed = (0..<12).map {
            ProgramDayRecord(id: ComposedWorkout.dayID(for: .push), programID: own.id, ownerID: user, name: LocalizedText(["nl": "Duwen"]), position: $0, updatedAt: now + Double($0))
        }
        let (shared, sharedDays, _) = programme(bench, days: 2)
        let (mine, myDays, _) = programme(bench, days: 2, owner: user)
        let records = book(exercises: [bench], programs: [own, shared, mine], days: composed + sharedDays + myDays)
        #expect(records.daysToShow(of: own.id).map(\.position) == Array((2..<12).reversed()))
        #expect(records.composedWorkoutCount(of: own.id) == 12)
        #expect(records.composedWorkoutCount(of: mine.id) == nil)
        #expect(records.composedProgram()?.id == own.id)
        #expect(!records.canChange(composed[0]) && !records.canChange(sharedDays[0]) && records.canChange(myDays[0]))
        // Shared first, then by days per week.
        #expect(records.programs().first?.id == shared.id)
    }

    @Test func removedDaysKeepTheirNameButLeaveTheProgramme() {
        let bench = exercise("Bench press")
        let (program, days, items) = programme(bench, days: 2, owner: user)
        var removed = days[1]
        removed.deleted = true
        let records = book(exercises: [bench], programs: [program], days: [days[0], removed], items: items)
        #expect(records.day(removed.id)?.name == removed.name)
        #expect(records.days(of: program.id).map(\.id) == [days[0].id])
    }

    @Test func exercisesComeInReadingOrder() {
        let names = ["Élévation latérale", "bench press", "Curl"]
        let records = book(exercises: names.map { exercise($0) })
        #expect(records.exercises().map { $0.name.text(preferring: ["nl"]) } == ["bench press", "Curl", "Élévation latérale"])
    }
}
