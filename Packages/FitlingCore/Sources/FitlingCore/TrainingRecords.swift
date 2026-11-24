#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

// The training rows of one user and the shared catalogue, and everything the app and the web read from them: which
// workout is next, what the coach says, the history and rules per exercise, how the next set is filled in. The app
// builds this from SwiftData, the web from Supabase; both write their own rows. Only rows that are not deleted, except
// programmes and days: a past workout keeps the name of a day that was removed later.

public struct ExerciseRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var ownerID: UUID?
    public var name: LocalizedText
    public var kind: String
    public var loadType: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var defaultStepKg: Double

    public init(
        id: UUID, ownerID: UUID?, name: LocalizedText, kind: String, loadType: String, primaryMuscles: [String],
        secondaryMuscles: [String], defaultStepKg: Double
    ) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.kind = kind
        self.loadType = loadType
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.defaultStepKg = defaultStepKg
    }
}

public struct ProgramRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var ownerID: UUID?
    public var name: LocalizedText
    public var daysPerWeek: Int
    public var deleted: Bool

    public init(id: UUID, ownerID: UUID?, name: LocalizedText, daysPerWeek: Int, deleted: Bool = false) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.daysPerWeek = daysPerWeek
        self.deleted = deleted
    }
}

public struct ProgramDayRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var programID: UUID
    public var ownerID: UUID?
    public var name: LocalizedText
    public var position: Int
    /// Seconds since 1970.
    public var updatedAt: Double
    public var deleted: Bool

    public init(id: UUID, programID: UUID, ownerID: UUID?, name: LocalizedText, position: Int, updatedAt: Double, deleted: Bool = false) {
        self.id = id
        self.programID = programID
        self.ownerID = ownerID
        self.name = name
        self.position = position
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

public struct ProgramItemRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var programDayID: UUID
    public var ownerID: UUID?
    public var exerciseID: UUID
    public var position: Int
    public var targetSets: Int
    public var repMin: Int
    public var repMax: Int
    public var restSeconds: Int

    public init(
        id: UUID, programDayID: UUID, ownerID: UUID?, exerciseID: UUID, position: Int, targetSets: Int, repMin: Int, repMax: Int,
        restSeconds: Int
    ) {
        self.id = id
        self.programDayID = programDayID
        self.ownerID = ownerID
        self.exerciseID = exerciseID
        self.position = position
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
    }
}

public struct ExerciseSettingRecord: Sendable, Equatable, Codable {
    public var exerciseID: UUID
    public var stepKg: Double
    public var repMin: Int?
    public var repMax: Int?
    /// Seconds since 1970; the newest of two settings for one exercise counts.
    public var updatedAt: Double

    public init(exerciseID: UUID, stepKg: Double, repMin: Int? = nil, repMax: Int? = nil, updatedAt: Double) {
        self.exerciseID = exerciseID
        self.stepKg = stepKg
        self.repMin = repMin
        self.repMax = repMax
        self.updatedAt = updatedAt
    }
}

public struct SessionRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var programDayID: UUID?
    public var performedOn: Day
    /// Seconds since 1970.
    public var startedAt: Double
    public var endedAt: Double?

    public init(id: UUID, programDayID: UUID?, performedOn: Day, startedAt: Double, endedAt: Double? = nil) {
        self.id = id
        self.programDayID = programDayID
        self.performedOn = performedOn
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct SetRecord: Sendable, Equatable, Codable {
    public var id: UUID
    public var sessionID: UUID
    public var exerciseID: UUID
    public var position: Int
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var isWarmup: Bool

    public init(id: UUID, sessionID: UUID, exerciseID: UUID, position: Int, weightKg: Double, reps: Int, rpe: Double? = nil, isWarmup: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.position = position
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
    }

    /// Nil for a warm-up set: it does not count towards progression, records or volume.
    public var workingSet: WorkingSet? {
        isWarmup ? nil : WorkingSet(weightKg: weightKg, reps: reps, rpe: rpe)
    }
}

/// What the training tab offers to do next.
public enum NextWorkoutRecord: Sendable, Equatable {
    case programDay(programID: UUID, dayID: UUID)
    case compose(TrainingFocus)
}

/// A note from the coach on one exercise.
public struct CoachNoteRecord: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Ready for more: the advice says how.
        case heavier(ProgressionAdvice)
        /// No progress for a while: another exercise for the same muscle.
        case switchTo(UUID)
    }

    public var exerciseID: UUID
    public var kind: Kind
}

/// What goes when a workout is thrown away: a composed day made for it alone, its exercises, and with the last day
/// its programme.
public struct DiscardCleanup: Sendable, Equatable {
    public var dayID: UUID
    public var itemIDs: [UUID]
    public var programID: UUID?

    public init(dayID: UUID, itemIDs: [UUID], programID: UUID?) {
        self.dayID = dayID
        self.itemIDs = itemIDs
        self.programID = programID
    }
}

/// The next set as the advice fills it in, in kilograms; nil where the user has to choose.
public struct SetDraft: Sendable, Equatable {
    public var weightKg: Double?
    public var reps: Int?
}

public struct TrainingRecords: Sendable {
    public let userID: UUID
    public let today: Day
    /// The user's languages, for names and their order.
    public let languages: [String]

    private let exerciseRows: [ExerciseRecord]
    private let programRows: [ProgramRecord]
    private let dayRows: [ProgramDayRecord]
    private let itemRows: [ProgramItemRecord]
    private let settingRows: [ExerciseSettingRecord]
    private let sessionRows: [SessionRecord]
    private let setRows: [SetRecord]
    private let sessionsByID: [UUID: SessionRecord]

    public init(
        userID: UUID, exercises: [ExerciseRecord], programs: [ProgramRecord], days: [ProgramDayRecord], items: [ProgramItemRecord],
        settings: [ExerciseSettingRecord], sessions: [SessionRecord], sets: [SetRecord], today: Day, languages: [String]
    ) {
        self.userID = userID
        self.today = today
        self.languages = languages
        // Shared rows and the user's own; another user's rows never count.
        exerciseRows = exercises.filter { $0.ownerID == nil || $0.ownerID == userID }
        programRows = programs.filter { $0.ownerID == nil || $0.ownerID == userID }
        dayRows = days
        itemRows = items
        settingRows = settings
        sessionRows = sessions
        setRows = sets
        sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Programmes

    /// The ready-made programmes first (fewest days first), then the user's own.
    public func programs() -> [ProgramRecord] {
        programRows.filter { !$0.deleted }.sorted { lhs, rhs in
            if (lhs.ownerID == nil) != (rhs.ownerID == nil) { return lhs.ownerID == nil }
            if lhs.daysPerWeek != rhs.daysPerWeek { return lhs.daysPerWeek < rhs.daysPerWeek }
            return lhs.name.text(preferring: languages) < rhs.name.text(preferring: languages)
        }
    }

    /// Also a removed one, as a past workout still names it.
    public func program(_ id: UUID) -> ProgramRecord? {
        programRows.first { $0.id == id }
    }

    public func days(of programID: UUID) -> [ProgramDayRecord] {
        dayRows.filter { $0.programID == programID && !$0.deleted }.sorted { $0.position < $1.position }
    }

    /// Also a removed one, as a past workout still names it.
    public func day(_ id: UUID) -> ProgramDayRecord? {
        dayRows.first { $0.id == id }
    }

    public func items(of dayID: UUID) -> [ProgramItemRecord] {
        itemRows.filter { $0.programDayID == dayID }.sorted { $0.position < $1.position }
    }

    public func exercise(_ id: UUID) -> ExerciseRecord? {
        exerciseRows.first { $0.id == id }
    }

    /// Shared and own exercises, by name in the user's language.
    public func exercises() -> [ExerciseRecord] {
        exerciseRows.sorted { Self.inOrder($0.name.text(preferring: languages), $1.name.text(preferring: languages)) }
    }

    /// For the programme of composed workouts the number of them; nil for every other programme.
    public func composedWorkoutCount(of programID: UUID) -> Int? {
        let count = days(of: programID).filter { ComposedWorkout.focus(of: $0.id) != nil }.count
        return count > 0 ? count : nil
    }

    /// Whether the programme screen may change the day: the user's own, and not a composed one. That is the record
    /// of one workout; another one is composed instead.
    public func canChange(_ day: ProgramDayRecord) -> Bool {
        day.ownerID == userID && ComposedWorkout.focus(of: day.id) == nil
    }

    /// How many of the composed workouts their programme shows.
    public static let composedDaysShown = 10

    /// The programme of composed workouts gets a day with every workout: it shows the newest first, and not all.
    public func daysToShow(of programID: UUID) -> [ProgramDayRecord] {
        let all = days(of: programID)
        guard all.contains(where: { ComposedWorkout.focus(of: $0.id) != nil }) else { return all }
        return Array(all.reversed().prefix(Self.composedDaysShown))
    }

    /// The programme of composed workouts, known by its days: so it is the same on every device and after a rename.
    /// With two, made on two devices that were offline, the one with the newest workout.
    public func composedProgram() -> ProgramRecord? {
        let withNewest = programs().filter { $0.ownerID == userID }.compactMap { program -> (program: ProgramRecord, newest: Double)? in
            let composed = days(of: program.id).filter { ComposedWorkout.focus(of: $0.id) != nil }
            guard let newest = composed.map(\.updatedAt).max() else { return nil }
            return (program: program, newest: newest)
        }
        return withNewest.max { $0.newest < $1.newest }?.program
    }

    // MARK: Workouts

    /// A workout that was started and not finished, if there is one.
    public func activeSession() -> SessionRecord? {
        sessionRows.filter { $0.endedAt == nil }.max { $0.startedAt < $1.startedAt }
    }

    public func finishedSessions(limit: Int = 20) -> [SessionRecord] {
        Array(sessionRows.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func sets(of sessionID: UUID) -> [SetRecord] {
        setRows.filter { $0.sessionID == sessionID }.sorted { $0.position < $1.position }
    }

    /// After a workout from a programme the day after it, round and round. After a composed one the focus whose
    /// turn it is, for the generator to make a new workout for.
    public func nextWorkout() -> NextWorkoutRecord? {
        for session in finishedSessions(limit: 10) {
            guard let lastID = session.programDayID, let last = day(lastID), let program = program(last.programID), !program.deleted else { continue }
            if ComposedWorkout.focus(of: lastID) != nil {
                return ComposedWorkout.nextFocus(after: composedWorkoutsDone()).map { NextWorkoutRecord.compose($0) }
            }
            let all = days(of: program.id)
            guard !all.isEmpty else { continue }
            let index = all.firstIndex { $0.id == last.id } ?? -1
            return .programDay(programID: program.id, dayID: all[(index + 1) % all.count].id)
        }
        return nil
    }

    /// When a workout is thrown away (TrainingStore.discard): a composed day was made for this one workout, so it goes
    /// too, unless another workout was done on it; with the last day its programme. Nil when nothing else goes.
    public func cleanup(discarding sessionID: UUID) -> DiscardCleanup? {
        guard let id = sessionsByID[sessionID]?.programDayID, ComposedWorkout.focus(of: id) != nil, let unused = day(id), !unused.deleted,
              unused.ownerID == userID, !sessionRows.contains(where: { $0.programDayID == id && $0.id != sessionID })
        else { return nil }
        let othersLeft = days(of: unused.programID).contains { $0.id != id }
        return DiscardCleanup(dayID: id, itemIDs: items(of: id).map(\.id), programID: othersLeft ? nil : unused.programID)
    }

    private func composedWorkoutsDone() -> [(focus: TrainingFocus, day: Day)] {
        finishedSessions(limit: Self.historyWorkouts).compactMap { session in
            guard let id = session.programDayID, let focus = ComposedWorkout.focus(of: id) else { return nil }
            return (focus: focus, day: session.performedOn)
        }
    }

    /// A set as it is stored: weight to the hundredth and 0...1000 kg, reps 0...1000, RPE to the half and 1...10.
    public static func loggedSet(weightKg: Double, reps: Int, rpe: Double?) -> (weightKg: Double, reps: Int, rpe: Double?) {
        (
            weightKg: min(max((weightKg * 100).rounded() / 100, 0), 1000),
            reps: min(max(reps, 0), 1000),
            rpe: rpe.map { min(max(($0 * 2).rounded() / 2, 1), 10) }
        )
    }

    // MARK: Progression

    /// Every workout with this exercise, working sets only (TASKS 4.5).
    public func history(of exerciseID: UUID, excluding sessionID: UUID? = nil) -> [ExerciseSession] {
        let sets = setRows.filter { $0.exerciseID == exerciseID && !$0.isWarmup && $0.sessionID != sessionID && sessionsByID[$0.sessionID] != nil }
        // Workouts on the same day by their start: which one is the last decides the advice.
        return Dictionary(grouping: sets, by: \.sessionID)
            .compactMap { id, sets -> (started: Double, exercise: ExerciseSession)? in
                guard let session = sessionsByID[id] else { return nil }
                return (session.startedAt, ExerciseSession(day: session.performedOn, sets: sets.sorted { $0.position < $1.position }.compactMap(\.workingSet)))
            }
            .sorted { $0.exercise.day != $1.exercise.day ? $0.exercise.day < $1.exercise.day : $0.started < $1.started }
            .map(\.exercise)
    }

    /// The user's own setting for an exercise; the newest when two devices made one.
    public func setting(for exerciseID: UUID) -> ExerciseSettingRecord? {
        settingRows.filter { $0.exerciseID == exerciseID }.max { $0.updatedAt < $1.updatedAt }
    }

    /// The user's own setting first, then the programme, then the exercise itself.
    public func rules(for exercise: ExerciseRecord, in item: ProgramItemRecord?) -> ExerciseRules {
        let setting = self.setting(for: exercise.id)
        var range = item.map { $0.repMin...$0.repMax } ?? 8...12
        if let low = setting?.repMin, let high = setting?.repMax, low <= high { range = low...high }
        return ExerciseRules(
            kind: ExerciseKind(rawValue: exercise.kind) ?? .compound,
            loadType: LoadType(rawValue: exercise.loadType) ?? .external,
            repRange: range,
            targetSets: item?.targetSets ?? 3,
            stepKg: setting?.stepKg ?? exercise.defaultStepKg
        )
    }

    /// The rules the last finished workout with the exercise was done by: those of its programme day, which for a
    /// composed workout is never refilled.
    public func rulesOfLastWorkout(for exercise: ExerciseRecord) -> ExerciseRules {
        let programDay = lastWorkout(with: exercise.id)?.programDayID.flatMap { day($0) }
        let item = programDay.flatMap { items(of: $0.id).first { $0.exerciseID == exercise.id } }
        return rules(for: exercise, in: item)
    }

    /// The advice outside a workout: by the rules of the last one.
    public func adviceAfterLastWorkout(for exercise: ExerciseRecord) -> ProgressionAdvice {
        ProgressionEngine.advise(history: history(of: exercise.id), rules: rulesOfLastWorkout(for: exercise), today: today)
    }

    /// The last finished workout with a working set of the exercise.
    private func lastWorkout(with exerciseID: UUID) -> SessionRecord? {
        let ids = Set(setRows.filter { $0.exerciseID == exerciseID && !$0.isWarmup }.map(\.sessionID))
        return ids.compactMap { sessionsByID[$0] }.filter { $0.endedAt != nil }.max { $0.startedAt < $1.startedAt }
    }

    public func advice(for exercise: ExerciseRecord, in item: ProgramItemRecord?, excluding sessionID: UUID? = nil) -> ProgressionAdvice {
        ProgressionEngine.advise(history: history(of: exercise.id, excluding: sessionID), rules: rules(for: exercise, in: item), today: today)
    }

    /// The next set from the advice: the weight it names and the reps to aim for (WorkoutViewModel.prefill).
    public func prefill(_ exercise: ExerciseRecord, in item: ProgramItemRecord?, excluding sessionID: UUID? = nil) -> SetDraft {
        let rules = self.rules(for: exercise, in: item)
        var draft = SetDraft(weightKg: nil, reps: rules.repRange.lowerBound)
        switch advice(for: exercise, in: item, excluding: sessionID) {
        case let .increase(weight), let .reduce(weight), let .easeBackIn(weight):
            draft.weightKg = weight
        case let .keepGoing(weight):
            draft.weightKg = weight
            // Aim for one more rep than last time at this weight, up to the top of the range.
            let last = history(of: exercise.id, excluding: sessionID).last?.sets.filter { $0.weightKg == weight }.map(\.reps).max()
            draft.reps = min(max((last ?? rules.repRange.lowerBound - 1) + 1, rules.repRange.lowerBound), rules.repRange.upperBound)
        case let .addRepsFirst(weight, targetReps):
            draft.weightKg = weight
            draft.reps = targetReps
        case .findStartingWeight, .makeHarder, .makeEasier:
            break
        }
        return draft
    }

    /// Records set in a workout, per exercise in the order given, to celebrate at the end.
    public func records(in sessionID: UUID, exerciseIDs: [UUID]) -> [(exerciseID: UUID, record: PersonalRecord)] {
        exerciseIDs.flatMap { exerciseID -> [(exerciseID: UUID, record: PersonalRecord)] in
            let working = sets(of: sessionID).filter { $0.exerciseID == exerciseID }.compactMap(\.workingSet)
            guard !working.isEmpty else { return [] }
            let session = ExerciseSession(day: today, sets: working)
            return ProgressionEngine.personalRecords(in: session, history: history(of: exerciseID, excluding: sessionID))
                .map { (exerciseID: exerciseID, record: $0) }
        }
    }

    /// Sets and tonnage per muscle in this week and the last (VolumeView).
    public func weeklyVolume() -> [Day: [MuscleGroup: MuscleVolume]] {
        let since = today.weekStart.adding(-7)
        var logged: [LoggedExercise] = []
        for exercise in exercises() {
            let primary = exercise.primaryMuscles.compactMap(MuscleGroup.init(rawValue:))
            let secondary = exercise.secondaryMuscles.compactMap(MuscleGroup.init(rawValue:))
            for session in history(of: exercise.id) where session.day >= since {
                logged.append(LoggedExercise(day: session.day, primaryMuscles: primary, secondaryMuscles: secondary, sets: session.sets))
            }
        }
        return ProgressionEngine.weeklyVolume(logged)
    }

    // MARK: Coach

    /// How far back the coach looks for exercises to say something about.
    public static let coachDays = 28
    /// How many finished workouts back the generator and the coach look.
    public static let historyWorkouts = 200

    /// Every exercise the user can do, with the day it was last done.
    public func workoutCandidates() -> [WorkoutCandidate] {
        let lastDone = lastDoneDays()
        let places = placesInReadyMadePrograms()
        return exercises().compactMap { exercise in
            let muscles = exercise.primaryMuscles.compactMap(MuscleGroup.init(rawValue:))
            guard !muscles.isEmpty, let kind = ExerciseKind(rawValue: exercise.kind) else { return nil }
            return WorkoutCandidate(id: exercise.id, kind: kind, primaryMuscles: muscles, preference: places[exercise.id], lastDone: lastDone[exercise.id])
        }
    }

    /// The finished workouts, newest first, each with its exercises in the order they were first done.
    public func workoutHistory() -> [[UUID]] {
        finishedSessions(limit: Self.historyWorkouts).map { session in
            var seen = Set<UUID>()
            return sets(of: session.id).filter { !$0.isWarmup }.map(\.exerciseID).filter { seen.insert($0).inserted }
        }
    }

    /// Where each exercise first appears in the ready-made programmes, fewest days first: squat, bench press, row.
    private func placesInReadyMadePrograms() -> [UUID: Int] {
        var places: [UUID: Int] = [:]
        for program in programs() where program.ownerID == nil {
            for day in days(of: program.id) {
                for item in items(of: day.id) where places[item.exerciseID] == nil {
                    places[item.exerciseID] = places.count
                }
            }
        }
        return places
    }

    /// Per exercise the day of the last finished workout with a working set of it.
    private func lastDoneDays() -> [UUID: Day] {
        var result: [UUID: Day] = [:]
        for session in finishedSessions(limit: Self.historyWorkouts) {
            for set in sets(of: session.id) where !set.isWarmup {
                if let known = result[set.exerciseID], known >= session.performedOn { continue }
                result[set.exerciseID] = session.performedOn
            }
        }
        return result
    }

    /// What the coach has to say about the exercises of the last weeks, most recent first: which can go heavier, and
    /// which have stalled with another exercise for the same muscle to try.
    public func coachNotes(limit: Int = 5) -> [CoachNoteRecord] {
        let since = today.adding(-Self.coachDays)
        let candidates = workoutCandidates()
        var notes: [CoachNoteRecord] = []
        // Most recent first; exercises of the same day by name, so the list keeps its order.
        let recent = lastDoneDays().filter { $0.value >= since }.compactMap { id, day in exercise(id).map { (exercise: $0, day: day) } }
        let ordered = recent.sorted { first, second in
            if first.day != second.day { return first.day > second.day }
            return Self.inOrder(first.exercise.name.text(preferring: languages), second.exercise.name.text(preferring: languages))
        }
        for (exercise, _) in ordered {
            guard notes.count < limit else { break }
            let history = history(of: exercise.id)
            if ProgressionEngine.isStalled(history: history),
               let candidate = candidates.first(where: { $0.id == exercise.id }),
               let other = WorkoutBuilder.alternative(to: candidate, from: candidates) {
                notes.append(CoachNoteRecord(exerciseID: exercise.id, kind: .switchTo(other.id)))
                continue
            }
            let advice = ProgressionEngine.advise(history: history, rules: rulesOfLastWorkout(for: exercise), today: today)
            switch advice {
            case .increase, .addRepsFirst, .makeHarder:
                notes.append(CoachNoteRecord(exerciseID: exercise.id, kind: .heavier(advice)))
            default:
                break
            }
        }
        return notes
    }

    /// Names in reading order, as a person sorts them: without regard to capitals or accents ("Élévation" with the
    /// E's), then as written so the order is fixed.
    static func inOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.folded
        let right = rhs.folded
        return left != right ? left < right : lhs < rhs
    }
}
