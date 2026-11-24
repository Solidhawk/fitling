import Foundation
import SwiftData
import FitlingCore

/// Programmes, workouts and the history the progression advice is based on, for one user.
@MainActor
struct TrainingStore {
    let context: ModelContext
    let userID: UUID
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init
    /// The language a name the user types is stored under.
    var language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "nl"

    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    // MARK: Programmes

    /// The ready-made programmes first (fewest days first), then the user's own (TrainingRecords.programs).
    func programs() -> [Program] {
        let owner: UUID? = userID
        let all = (try? context.fetch(FetchDescriptor<Program>(
            predicate: #Predicate<Program> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ordering(programs: all).programs().compactMap { byID[$0.id] }
    }

    func program(_ id: UUID) -> Program? {
        var descriptor = FetchDescriptor<Program>(predicate: #Predicate<Program> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func days(of program: Program) -> [ProgramDay] {
        let programID = program.id
        return (try? context.fetch(FetchDescriptor<ProgramDay>(
            predicate: #Predicate<ProgramDay> { $0.programID == programID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        ))) ?? []
    }

    func day(_ id: UUID) -> ProgramDay? {
        var descriptor = FetchDescriptor<ProgramDay>(predicate: #Predicate<ProgramDay> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func items(of day: ProgramDay) -> [ProgramExercise] {
        let dayID = day.id
        return (try? context.fetch(FetchDescriptor<ProgramExercise>(
            predicate: #Predicate<ProgramExercise> { $0.programDayID == dayID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        ))) ?? []
    }

    func exercise(_ id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Shared and own exercises, by name in the user's language (TrainingRecords.exercises).
    func exercises() -> [Exercise] {
        let owner: UUID? = userID
        let all = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ordering(exercises: all).exercises().compactMap { byID[$0.id] }
    }

    /// The user's own copy of a programme, to change freely. Days and exercises are copied with
    /// new ids; the shared original stays as it is.
    @discardableResult
    func copy(_ program: Program, named name: String) -> Program {
        let copy = Program(id: UUID(), ownerID: userID, name: LocalizedText([language: name]), daysPerWeek: program.daysPerWeek, updatedAt: now())
        context.insert(copy)
        for day in days(of: program) {
            let newDay = ProgramDay(id: UUID(), programID: copy.id, ownerID: userID, name: day.name, position: day.position, updatedAt: now())
            context.insert(newDay)
            for item in items(of: day) {
                context.insert(ProgramExercise(
                    id: UUID(), programDayID: newDay.id, ownerID: userID, exerciseID: item.exerciseID, position: item.position,
                    targetSets: item.targetSets, repRange: item.repMin...item.repMax, restSeconds: item.restSeconds, updatedAt: now()
                ))
            }
        }
        try? context.save()
        return copy
    }

    /// A new, empty programme of the user's own with one day per training day.
    @discardableResult
    func createProgram(named name: String, daysPerWeek: Int, dayName: (Int) -> String) -> Program {
        let program = Program(id: UUID(), ownerID: userID, name: LocalizedText([language: name]), daysPerWeek: min(max(daysPerWeek, 1), 7), updatedAt: now())
        context.insert(program)
        for position in 0..<program.daysPerWeek {
            context.insert(ProgramDay(
                id: UUID(), programID: program.id, ownerID: userID, name: LocalizedText([language: dayName(position + 1)]),
                position: position, updatedAt: now()
            ))
        }
        try? context.save()
        return program
    }

    func rename(_ program: Program, to name: String) {
        guard program.ownerID == userID else { return }
        program.name = LocalizedText([language: name])
        touch(program)
    }

    func delete(_ program: Program) {
        guard program.ownerID == userID else { return }
        program.deletedAt = now()
        touch(program)
    }

    @discardableResult
    func add(_ exercise: Exercise, to day: ProgramDay, sets: Int, repRange: ClosedRange<Int>, restSeconds: Int) -> ProgramExercise? {
        guard day.ownerID == userID else { return nil }
        let item = ProgramExercise(
            id: UUID(), programDayID: day.id, ownerID: userID, exerciseID: exercise.id, position: (items(of: day).map(\.position).max() ?? -1) + 1,
            targetSets: min(max(sets, 1), 10), repRange: repRange, restSeconds: min(max(restSeconds, 0), 900), updatedAt: now()
        )
        context.insert(item)
        try? context.save()
        return item
    }

    func update(_ item: ProgramExercise, sets: Int, repRange: ClosedRange<Int>, restSeconds: Int) {
        guard item.ownerID == userID else { return }
        item.targetSets = min(max(sets, 1), 10)
        item.repMin = repRange.lowerBound
        item.repMax = repRange.upperBound
        item.restSeconds = min(max(restSeconds, 0), 900)
        touch(item)
    }

    func remove(_ item: ProgramExercise) {
        guard item.ownerID == userID else { return }
        item.deletedAt = now()
        touch(item)
    }

    /// For the programme of composed workouts the number of them; nil for every other programme.
    func composedWorkoutCount(of program: Program) -> Int? {
        records().composedWorkoutCount(of: program.id)
    }

    /// Whether the programme screen may change the day: the user's own, and not a composed one. That is the record
    /// of one workout; another one is composed instead.
    func canChange(_ day: ProgramDay) -> Bool {
        TrainingRecords(
            userID: userID, exercises: [], programs: [], days: [], items: [], settings: [], sessions: [], sets: [], today: today, languages: languages
        ).canChange(day.trainingRecord)
    }

    // MARK: Workouts

    /// A workout that was started and not finished, if there is one.
    func activeSession() -> WorkoutSession? {
        let userID = userID
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.userID == userID && $0.endedAt == nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func finishedSessions(limit: Int = 20) -> [WorkoutSession] {
        let userID = userID
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.userID == userID && $0.endedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func start(_ day: ProgramDay?) -> WorkoutSession {
        let session = WorkoutSession(id: UUID(), userID: userID, programDayID: day?.id, performedOn: today, startedAt: now(), updatedAt: now())
        context.insert(session)
        try? context.save()
        return session
    }

    func finish(_ session: WorkoutSession) {
        session.endedAt = max(now(), session.startedAt)
        touch(session)
    }

    /// Throws a workout away with its sets, for a workout that was started by mistake. A composed day was made
    /// for this one workout, so it goes too, unless another workout was done on it, and with the last day its programme.
    func discard(_ session: WorkoutSession) {
        session.deletedAt = now()
        for set in sets(of: session) {
            set.deletedAt = now()
            set.updatedAt = now()
            set.needsPush = true
        }
        touch(session)
        removeComposedDayIfUnused(session.programDayID)
    }

    private func removeComposedDayIfUnused(_ id: UUID?) {
        guard let id, ComposedWorkout.focus(of: id) != nil, let unused = day(id), unused.ownerID == userID else { return }
        let dayID: UUID? = id
        let uses = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.programDayID == dayID && $0.deletedAt == nil }
        ))) ?? 0
        guard uses == 0 else { return }
        for item in items(of: unused) { remove(item) }
        unused.deletedAt = now()
        touch(unused)
        if let program = program(unused.programID), days(of: program).isEmpty { delete(program) }
    }

    func sets(of session: WorkoutSession) -> [WorkoutSet] {
        let sessionID = session.id
        return (try? context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { $0.sessionID == sessionID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        ))) ?? []
    }

    @discardableResult
    func log(in session: WorkoutSession, exercise: Exercise, weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool) -> WorkoutSet {
        let set = WorkoutSet(
            id: UUID(), userID: userID, sessionID: session.id, exerciseID: exercise.id,
            position: (sets(of: session).map(\.position).max() ?? -1) + 1,
            weightKg: min(max((weightKg * 100).rounded() / 100, 0), 1000), reps: min(max(reps, 0), 1000),
            rpe: rpe.map { min(max(($0 * 2).rounded() / 2, 1), 10) }, isWarmup: isWarmup, updatedAt: now()
        )
        context.insert(set)
        session.updatedAt = now()
        session.needsPush = true
        try? context.save()
        return set
    }

    func remove(_ set: WorkoutSet) {
        set.deletedAt = now()
        touch(set)
    }

    /// How many of the composed workouts their programme shows.
    static let composedDaysShown = TrainingRecords.composedDaysShown

    /// The programme of composed workouts gets a day with every workout: it shows the newest first, and not all.
    func daysToShow(of program: Program) -> [ProgramDay] {
        records().daysToShow(of: program.id).compactMap { day($0.id) }
    }

    /// After a workout from a programme the day after it, round and round. After a composed one the focus whose
    /// turn it is, for the generator to make a new workout for.
    func nextWorkout() -> NextWorkout? {
        switch records().nextWorkout() {
        case let .programDay(programID, dayID):
            guard let program = program(programID), let day = day(dayID) else { return nil }
            return .programDay(program: program, day: day)
        case let .compose(focus):
            return .compose(focus)
        case nil:
            return nil
        }
    }


    // MARK: Progression

    /// Every workout with this exercise, working sets only (TASKS 4.5).
    func history(of exerciseID: UUID, excluding session: WorkoutSession? = nil) -> [ExerciseSession] {
        records().history(of: exerciseID, excluding: session?.id)
    }

    /// The user's own setting for an exercise, to change; the newest when two devices made one.
    func setting(for exerciseID: UUID) -> ExerciseSetting? {
        let userID = userID
        var descriptor = FetchDescriptor<ExerciseSetting>(
            predicate: #Predicate<ExerciseSetting> { $0.userID == userID && $0.exerciseID == exerciseID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The user's own weight step for an exercise: dumbbells per 2 kg at one gym, per 2.5 at another.
    func saveStep(_ stepKg: Double, for exercise: Exercise) {
        let step = min(max(stepKg, 0.25), 25)
        if let setting = self.setting(for: exercise.id) {
            setting.stepKg = step
            touch(setting)
        } else {
            context.insert(ExerciseSetting(id: UUID(), userID: userID, exerciseID: exercise.id, stepKg: step, updatedAt: now()))
            try? context.save()
        }
    }

    /// The user's own setting first, then the programme, then the exercise itself.
    func rules(for exercise: Exercise, in item: ProgramExercise?) -> ExerciseRules {
        records().rules(for: exercise.trainingRecord, in: item?.trainingRecord)
    }

    /// The rules the last finished workout with the exercise was done by: those of its programme day, which for a
    /// composed workout is never refilled.
    func rulesOfLastWorkout(for exercise: Exercise) -> ExerciseRules {
        records().rulesOfLastWorkout(for: exercise.trainingRecord)
    }

    /// The advice outside a workout: by the rules of the last one.
    func adviceAfterLastWorkout(for exercise: Exercise) -> ProgressionAdvice {
        records().adviceAfterLastWorkout(for: exercise.trainingRecord)
    }


    func advice(for exercise: Exercise, in item: ProgramExercise?, excluding session: WorkoutSession? = nil) -> ProgressionAdvice {
        records().advice(for: exercise.trainingRecord, in: item?.trainingRecord, excluding: session?.id)
    }

    private func touch(_ model: some SyncableModel) {
        model.updatedAt = now()
        model.needsPush = true
        try? context.save()
    }

    // MARK: Coach

    /// How far back the coach looks for exercises to say something about.
    static let coachDays = TrainingRecords.coachDays
    /// How many finished workouts back the generator and the coach look.
    static let historyWorkouts = TrainingRecords.historyWorkouts

    /// Every exercise the user can do, with the day it was last done.
    func workoutCandidates() -> [WorkoutCandidate] {
        records().workoutCandidates()
    }

    /// The finished workouts, newest first, each with its exercises in the order they were first done.
    func workoutHistory() -> [[UUID]] {
        records().workoutHistory()
    }

    /// A composed workout as a new day in the user's own programme of composed workouts. An earlier day is never
    /// renamed or refilled: the workout done on it takes its name, sets and reps from it.
    @discardableResult
    func compose(_ plan: [PlannedExercise], for focus: TrainingFocus, programName: String, dayName: String) -> ProgramDay {
        let program: Program
        if let existing = composedProgram() {
            program = existing
        } else {
            program = Program(id: UUID(), ownerID: userID, name: LocalizedText([language: programName]), daysPerWeek: 1, updatedAt: now())
            context.insert(program)
        }
        let newDay = ProgramDay(
            id: ComposedWorkout.dayID(for: focus), programID: program.id, ownerID: userID, name: LocalizedText([language: dayName]),
            position: (days(of: program).map(\.position).max() ?? -1) + 1, updatedAt: now()
        )
        context.insert(newDay)
        try? context.save()
        for planned in plan {
            guard let exercise = exercise(planned.exerciseID) else { continue }
            add(exercise, to: newDay, sets: planned.sets, repRange: planned.repRange, restSeconds: planned.restSeconds)
        }
        return newDay
    }

    /// The programme of composed workouts, known by its days: so it is the same on every device and after a rename.
    private func composedProgram() -> Program? {
        records().composedProgram().flatMap { program($0.id) }
    }

    /// What the coach has to say about the exercises of the last weeks, most recent first: which
    /// can go heavier, and which have stalled with another exercise for the same muscle to try.
    func coachNotes(limit: Int = 5) -> [CoachNote] {
        records().coachNotes(limit: limit).compactMap { note in
            guard let exercise = exercise(note.exerciseID) else { return nil }
            switch note.kind {
            case let .heavier(advice):
                return CoachNote(exercise: exercise, kind: .heavier(advice))
            case let .switchTo(otherID):
                return self.exercise(otherID).map { CoachNote(exercise: exercise, kind: .switchTo($0)) }
            }
        }
    }

    // MARK: Records

    /// The user's languages, for names and their order.
    var languages: [String] {
        [language] + Locale.preferredLanguages
    }

    /// Everything on this device that FitlingCore reads: shared and own rows, sessions and sets that are not
    /// deleted, and programmes and days also when removed (a past workout keeps the name of its day).
    func records() -> TrainingRecords {
        let owner: UUID? = userID
        let userID = userID
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let programs = (try? context.fetch(FetchDescriptor<Program>(predicate: #Predicate<Program> { $0.ownerID == nil || $0.ownerID == owner }))) ?? []
        let days = (try? context.fetch(FetchDescriptor<ProgramDay>(predicate: #Predicate<ProgramDay> { $0.ownerID == nil || $0.ownerID == owner }))) ?? []
        let items = (try? context.fetch(FetchDescriptor<ProgramExercise>(
            predicate: #Predicate<ProgramExercise> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let settings = (try? context.fetch(FetchDescriptor<ExerciseSetting>(
            predicate: #Predicate<ExerciseSetting> { $0.userID == userID && $0.deletedAt == nil }
        ))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.userID == userID && $0.deletedAt == nil }
        ))) ?? []
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { $0.userID == userID && $0.deletedAt == nil }
        ))) ?? []
        return TrainingRecords(
            userID: userID, exercises: exercises.map(\.trainingRecord), programs: programs.map(\.trainingRecord), days: days.map(\.trainingRecord),
            items: items.map(\.trainingRecord), settings: settings.map(\.trainingRecord), sessions: sessions.compactMap(\.trainingRecord), sets: sets.map(\.trainingRecord),
            today: today, languages: languages
        )
    }

    /// Only the rows a list needs, for ordering it.
    private func ordering(programs: [Program] = [], exercises: [Exercise] = []) -> TrainingRecords {
        TrainingRecords(
            userID: userID, exercises: exercises.map(\.trainingRecord), programs: programs.map(\.trainingRecord), days: [], items: [], settings: [],
            sessions: [], sets: [], today: today, languages: languages
        )
    }
}

/// What the training tab offers to do next.
enum NextWorkout {
    case programDay(program: Program, day: ProgramDay)
    case compose(TrainingFocus)
}

/// A note from the coach on one exercise.
struct CoachNote: Identifiable {
    enum Kind: Equatable {
        /// Ready for more: the advice says how.
        case heavier(ProgressionAdvice)
        /// No progress for a while: another exercise for the same muscle.
        case switchTo(Exercise)
    }

    let exercise: Exercise
    let kind: Kind
    var id: UUID { exercise.id }
}

// The SwiftData rows as FitlingCore reads them.

extension Exercise {
    var trainingRecord: ExerciseRecord {
        ExerciseRecord(
            id: id, ownerID: ownerID, name: name, kind: kind, loadType: loadType, primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles, defaultStepKg: defaultStepKg
        )
    }
}

extension Program {
    var trainingRecord: ProgramRecord {
        ProgramRecord(id: id, ownerID: ownerID, name: name, daysPerWeek: daysPerWeek, deleted: deletedAt != nil)
    }
}

extension ProgramDay {
    var trainingRecord: ProgramDayRecord {
        ProgramDayRecord(
            id: id, programID: programID, ownerID: ownerID, name: name, position: position,
            updatedAt: updatedAt.timeIntervalSince1970, deleted: deletedAt != nil
        )
    }
}

extension ProgramExercise {
    var trainingRecord: ProgramItemRecord {
        ProgramItemRecord(
            id: id, programDayID: programDayID, ownerID: ownerID, exerciseID: exerciseID, position: position, targetSets: targetSets,
            repMin: repMin, repMax: repMax, restSeconds: restSeconds
        )
    }
}

extension ExerciseSetting {
    var trainingRecord: ExerciseSettingRecord {
        ExerciseSettingRecord(exerciseID: exerciseID, stepKg: stepKg, repMin: repMin, repMax: repMax, updatedAt: updatedAt.timeIntervalSince1970)
    }
}

extension WorkoutSession {
    /// Nil for a session whose day cannot be read; it never counts.
    var trainingRecord: SessionRecord? {
        Day(isoString: performedOn).map {
            SessionRecord(
                id: id, programDayID: programDayID, performedOn: $0, startedAt: startedAt.timeIntervalSince1970,
                endedAt: endedAt?.timeIntervalSince1970
            )
        }
    }
}

extension WorkoutSet {
    var trainingRecord: SetRecord {
        SetRecord(id: id, sessionID: sessionID, exerciseID: exerciseID, position: position, weightKg: weightKg, reps: reps, rpe: rpe, isWarmup: isWarmup)
    }
}
