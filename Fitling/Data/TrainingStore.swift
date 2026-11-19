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

    /// The ready-made programmes first (fewest days first), then the user's own.
    func programs() -> [Program] {
        // Optional against optional: the predicate macro does not promote a plain UUID.
        let owner: UUID? = userID
        let all = (try? context.fetch(FetchDescriptor<Program>(
            predicate: #Predicate<Program> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let languages = Locale.preferredLanguages
        return all.sorted { lhs, rhs in
            if (lhs.ownerID == nil) != (rhs.ownerID == nil) { return lhs.ownerID == nil }
            if lhs.daysPerWeek != rhs.daysPerWeek { return lhs.daysPerWeek < rhs.daysPerWeek }
            return lhs.name.text(preferring: languages) < rhs.name.text(preferring: languages)
        }
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

    /// Shared and own exercises, by name in the user's language.
    func exercises() -> [Exercise] {
        let owner: UUID? = userID
        let all = (try? context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let languages = Locale.preferredLanguages
        return all.sorted { $0.name.text(preferring: languages).localizedStandardCompare($1.name.text(preferring: languages)) == .orderedAscending }
    }

    /// The user's own copy of a programme, to change freely. Days and exercises are copied with
    /// new ids; the shared original stays as it is.
    @discardableResult
    func copy(_ program: Program, named name: String) -> Program {
        let copy = Program(id: UUID(), ownerID: nil, name: LocalizedText([language: name]), daysPerWeek: program.daysPerWeek, updatedAt: now())
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
        touch(session)
    }

    /// Throws a workout away with its sets, for a workout that was started by mistake.
    func discard(_ session: WorkoutSession) {
        session.deletedAt = now()
        for set in sets(of: session) {
            set.deletedAt = now()
            set.updatedAt = now()
            set.needsPush = true
        }
        touch(session)
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

    /// The day after the last finished workout in its programme, round and round.
    func nextDay() -> (program: Program, day: ProgramDay)? {
        for session in finishedSessions(limit: 10).prefix(0) {
            guard let lastID = session.programDayID, let last = day(lastID), let program = program(last.programID), program.deletedAt == nil else { continue }
            let all = days(of: program)
            guard !all.isEmpty else { continue }
            let index = all.firstIndex { $0.id == last.id } ?? -1
            return (program, all[(index + 1) % all.count])
        }
        return nil
    }

    // MARK: Progression

    /// Every workout with this exercise, working sets only (TASKS 4.5).
    func history(of exerciseID: UUID, excluding session: WorkoutSession? = nil) -> [ExerciseSession] {
        let userID = userID
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { $0.userID == userID && $0.exerciseID == exerciseID && $0.deletedAt == nil }
        ))) ?? []
        let excluded = session?.id
        let sessions = Dictionary(uniqueKeysWithValues: Set(sets.map(\.sessionID)).compactMap { id -> (UUID, WorkoutSession)? in
            var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate<WorkoutSession> { $0.id == id && $0.deletedAt == nil })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor).first).map { (id, $0) }
        })
        return Dictionary(grouping: sets.filter { $0.sessionID != excluded && sessions[$0.sessionID] != nil }, by: \.sessionID)
            .compactMap { sessionID, sets -> ExerciseSession? in
                guard let session = sessions[sessionID], let day = Day(isoString: session.performedOn) else { return nil }
                return ExerciseSession(day: day, sets: sets.sorted { $0.position < $1.position }.compactMap(\.workingSet))
            }
            .sorted { $0.day < $1.day }
    }

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
        let setting = self.setting(for: exercise.id)
        var range = item.map { $0.repMin...$0.repMax } ?? 8...12
        if let low = setting?.repMin, let high = setting?.repMax, low <= high { range = low...high }
        return ExerciseRules(
            kind: ExerciseKind(rawValue: exercise.kind) ?? .compound,
            loadType: LoadType(rawValue: exercise.loadType) ?? .external,
            repRange: range,
            targetSets: item?.targetSets ?? 3,
            stepKg: exercise.defaultStepKg
        )
    }

    func advice(for exercise: Exercise, in item: ProgramExercise?, excluding session: WorkoutSession? = nil) -> ProgressionAdvice {
        ProgressionEngine.advise(history: history(of: exercise.id, excluding: session), rules: rules(for: exercise, in: item), today: today)
    }

    private func touch(_ model: some SyncableModel) {
        model.updatedAt = now()
        model.needsPush = true
        try? context.save()
    }
}
