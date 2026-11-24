#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The training tab for the web (phase 4): what TrainingStore, WorkoutViewModel and the progress screens read on
// iOS, from the same TrainingRecords. Ids go out in lower case, as Postgres writes them.

/// The user's training rows and the shared catalogue, as the web read them from Supabase.
struct TrainingInput: Decodable {
    let userID: UUID
    let today: String
    let languages: [String]
    let exercises: [ExerciseRecord]
    let programs: [ProgramRecord]
    let days: [ProgramDayRecord]
    let items: [ProgramItemRecord]
    let settings: [ExerciseSettingRecord]
    let sessions: [SessionRecord]
    let sets: [SetRecord]

    func records() throws -> TrainingRecords {
        TrainingRecords(
            userID: userID, exercises: exercises, programs: programs, days: days, items: items, settings: settings, sessions: sessions,
            sets: sets, today: try day(today, "today"), languages: languages
        )
    }
}

func lower(_ id: UUID) -> String {
    id.uuidString.lowercased()
}

struct AdviceOutput: Encodable {
    /// findStartingWeight, keepGoing, increase, addRepsFirst, reduce, easeBackIn, makeHarder or makeEasier.
    let kind: String
    var weightKg: Double?
    var targetReps: Int?

    init(_ advice: ProgressionAdvice) {
        switch advice {
        case .findStartingWeight: kind = "findStartingWeight"
        case let .keepGoing(weight): (kind, weightKg) = ("keepGoing", weight)
        case let .increase(weight): (kind, weightKg) = ("increase", weight)
        case let .addRepsFirst(weight, reps): (kind, weightKg, targetReps) = ("addRepsFirst", weight, reps)
        case let .reduce(weight): (kind, weightKg) = ("reduce", weight)
        case let .easeBackIn(weight): (kind, weightKg) = ("easeBackIn", weight)
        case .makeHarder: kind = "makeHarder"
        case .makeEasier: kind = "makeEasier"
        }
    }
}

struct RecordOutput: Encodable {
    /// weight, estimatedOneRepMax or reps.
    let kind: String
    let kg: Double
    var count: Int?

    init(_ record: PersonalRecord) {
        switch record {
        case let .weight(kg): (kind, self.kg) = ("weight", kg)
        case let .estimatedOneRepMax(kg): (kind, self.kg) = ("estimatedOneRepMax", kg)
        case let .reps(count, kg): (kind, self.kg, self.count) = ("reps", kg, count)
        }
    }
}

struct TrainingRequest: Decodable {
    let training: TrainingInput
}

// MARK: The tab

struct ProgramSummary: Encodable {
    let id: String
    let name: String
    let shared: Bool
    let daysPerWeek: Int
    /// For the programme of composed workouts the number of them.
    let composedCount: Int?
}

struct SessionSummary: Encodable {
    let id: String
    /// The name of its programme day; nil for a free workout.
    let title: String?
    let startedAt: Double
    let setCount: Int
}

struct NextOutput: Encodable {
    /// programDay or compose.
    let kind: String
    var programID: String?
    var dayID: String?
    var dayName: String?
    var programName: String?
    var focus: String?
}

struct CoachOutput: Encodable {
    let exerciseID: String
    let name: String
    /// heavier or switchTo.
    let kind: String
    var advice: AdviceOutput?
    var otherID: String?
    var otherName: String?
}

struct OverviewAnswer: Encodable {
    let programs: [ProgramSummary]
    let active: SessionSummary?
    let next: NextOutput?
    let recent: [SessionSummary]
    let coach: [CoachOutput]
}

func summary(_ session: SessionRecord, in records: TrainingRecords) -> SessionSummary {
    SessionSummary(
        id: lower(session.id), title: session.programDayID.flatMap { records.day($0) }.map { $0.name.text(preferring: records.languages) },
        startedAt: session.startedAt, setCount: records.sets(of: session.id).filter { !$0.isWarmup }.count
    )
}

/// The training tab (TrainingViewModel.reload): the workout under way or the next one, the coach, the programmes and
/// the last ten workouts.
func trainingOverview(_ request: TrainingRequest) throws -> OverviewAnswer {
    let records = try request.training.records()
    let languages = records.languages
    let next: NextOutput? = switch records.nextWorkout() {
    case let .programDay(programID, dayID):
        NextOutput(
            kind: "programDay", programID: lower(programID), dayID: lower(dayID), dayName: records.day(dayID)?.name.text(preferring: languages),
            programName: records.program(programID)?.name.text(preferring: languages)
        )
    case let .compose(focus):
        NextOutput(kind: "compose", focus: focus.rawValue)
    case nil:
        nil
    }
    let coach = records.coachNotes().compactMap { note -> CoachOutput? in
        guard let exercise = records.exercise(note.exerciseID) else { return nil }
        let name = exercise.name.text(preferring: languages)
        switch note.kind {
        case let .heavier(advice):
            return CoachOutput(exerciseID: lower(exercise.id), name: name, kind: "heavier", advice: AdviceOutput(advice))
        case let .switchTo(otherID):
            return records.exercise(otherID).map {
                CoachOutput(exerciseID: lower(exercise.id), name: name, kind: "switchTo", otherID: lower(otherID), otherName: $0.name.text(preferring: languages))
            }
        }
    }
    return OverviewAnswer(
        programs: records.programs().map {
            ProgramSummary(
                id: lower($0.id), name: $0.name.text(preferring: languages), shared: $0.ownerID == nil, daysPerWeek: $0.daysPerWeek,
                composedCount: records.composedWorkoutCount(of: $0.id)
            )
        },
        active: records.activeSession().map { summary($0, in: records) },
        next: next,
        recent: records.finishedSessions(limit: 10).map { summary($0, in: records) },
        coach: coach
    )
}

// MARK: A programme

struct ProgramRequest: Decodable {
    let training: TrainingInput
    let programID: UUID
}

struct ProgramItemOutput: Encodable {
    let id: String
    let exerciseID: String
    let exerciseName: String
    let targetSets: Int
    let repMin: Int
    let repMax: Int
    let restSeconds: Int
}

struct DayOutput: Encodable {
    let id: String
    let name: String
    /// A composed day carries its date in its title; `updatedAt` is when it was made.
    let composed: Bool
    let updatedAt: Double
    let canChange: Bool
    let items: [ProgramItemOutput]
}

struct ProgramAnswer: Encodable {
    let id: String
    let name: String
    let own: Bool
    let days: [DayOutput]
}

/// One programme with the days it shows (ProgramDetailView): the newest composed workouts first, at most ten.
func programDetail(_ request: ProgramRequest) throws -> ProgramAnswer {
    let records = try request.training.records()
    guard let program = records.program(request.programID) else { throw CallError(description: "unknown programme") }
    let languages = records.languages
    return ProgramAnswer(
        id: lower(program.id), name: program.name.text(preferring: languages), own: program.ownerID == records.userID,
        days: records.daysToShow(of: program.id).map { day in
            DayOutput(
                id: lower(day.id), name: day.name.text(preferring: languages), composed: ComposedWorkout.focus(of: day.id) != nil,
                updatedAt: day.updatedAt, canChange: records.canChange(day),
                items: records.items(of: day.id).map { item in
                    ProgramItemOutput(
                        id: lower(item.id), exerciseID: lower(item.exerciseID),
                        exerciseName: records.exercise(item.exerciseID)?.name.text(preferring: languages) ?? "",
                        targetSets: item.targetSets, repMin: item.repMin, repMax: item.repMax, restSeconds: item.restSeconds
                    )
                }
            )
        }
    )
}

// MARK: Exercises

struct ExerciseOutput: Encodable {
    let id: String
    let name: String
    let kind: String
    let primaryMuscles: [String]
    /// Whether a working set of it was ever logged (ExerciseProgressList).
    let done: Bool
}

/// Shared and own exercises by name, for the picker and the progress list.
func trainingExercises(_ request: TrainingRequest) throws -> [ExerciseOutput] {
    let records = try request.training.records()
    return records.exercises().map {
        ExerciseOutput(
            id: lower($0.id), name: $0.name.text(preferring: records.languages), kind: $0.kind, primaryMuscles: $0.primaryMuscles,
            done: !records.history(of: $0.id).isEmpty
        )
    }
}

// MARK: A workout

struct WorkoutRequest: Decodable {
    let training: TrainingInput
    let sessionID: UUID
    /// Exercises the user added during this workout and has not logged yet, in the order added.
    let added: [UUID]
    let usesPounds: Bool
}

struct RulesOutput: Encodable {
    let repMin: Int
    let repMax: Int
    let targetSets: Int
    let stepKg: Double
}

struct DraftOutput: Encodable {
    /// In the user's unit, to the hundredth.
    let weight: Double?
    let reps: Int?
}

struct EntryOutput: Encodable {
    let exerciseID: String
    let name: String
    let itemID: String?
    let restSeconds: Int
    let rules: RulesOutput
    let advice: AdviceOutput
    let draft: DraftOutput
}

struct WorkoutAnswer: Encodable {
    let title: String?
    let entries: [EntryOutput]
}

/// The default rest after a set of an exercise the user added (WorkoutViewModel.defaultRestSeconds).
let defaultRestSeconds = 120

/// One workout (WorkoutViewModel): the exercises of its day, then those logged on another device or added during it,
/// each with its rules, the advice and the next set filled in.
func workout(_ request: WorkoutRequest) throws -> WorkoutAnswer {
    let records = try request.training.records()
    let unit: WeightUnit = request.usesPounds ? .pounds : .kilograms
    let session = records.activeSession().flatMap { $0.id == request.sessionID ? $0 : nil }
        ?? records.finishedSessions(limit: .max).first { $0.id == request.sessionID }
    guard let session else { throw CallError(description: "unknown workout") }
    var entries: [(exercise: ExerciseRecord, item: ProgramItemRecord?)] = []
    if let dayID = session.programDayID {
        entries = records.items(of: dayID).compactMap { item in records.exercise(item.exerciseID).map { (exercise: $0, item: item) } }
    }
    for exerciseID in records.sets(of: session.id).map(\.exerciseID) + request.added where !entries.contains(where: { $0.exercise.id == exerciseID }) {
        if let exercise = records.exercise(exerciseID) { entries.append((exercise: exercise, item: nil)) }
    }
    return WorkoutAnswer(
        title: session.programDayID.flatMap { records.day($0) }.map { $0.name.text(preferring: records.languages) },
        entries: entries.map { entry in
            let rules = records.rules(for: entry.exercise, in: entry.item)
            let draft = records.prefill(entry.exercise, in: entry.item, excluding: session.id)
            return EntryOutput(
                exerciseID: lower(entry.exercise.id), name: entry.exercise.name.text(preferring: records.languages), itemID: entry.item.map { lower($0.id) },
                restSeconds: entry.item?.restSeconds ?? defaultRestSeconds,
                rules: RulesOutput(repMin: rules.repRange.lowerBound, repMax: rules.repRange.upperBound, targetSets: rules.targetSets, stepKg: rules.stepKg),
                advice: AdviceOutput(records.advice(for: entry.exercise, in: entry.item, excluding: session.id)),
                draft: DraftOutput(weight: draft.weightKg.map { (unit.value(fromKilograms: $0) * 100).rounded() / 100 }, reps: draft.reps)
            )
        }
    )
}

struct RecordsRequest: Decodable {
    let training: TrainingInput
    let sessionID: UUID
    let exerciseIDs: [UUID]
}

struct FoundRecord: Encodable {
    let exerciseID: String
    let name: String
    let record: RecordOutput
}

/// Records set in a workout, to celebrate when it is finished.
func workoutRecords(_ request: RecordsRequest) throws -> [FoundRecord] {
    let records = try request.training.records()
    return records.records(in: request.sessionID, exerciseIDs: request.exerciseIDs).compactMap { found in
        records.exercise(found.exerciseID).map {
            FoundRecord(exerciseID: lower(found.exerciseID), name: $0.name.text(preferring: records.languages), record: RecordOutput(found.record))
        }
    }
}

struct DiscardRequest: Decodable {
    let training: TrainingInput
    let sessionID: UUID
}

struct DiscardAnswer: Encodable {
    let dayID: String?
    let itemIDs: [String]
    let programID: String?
}

/// What goes with a workout that is thrown away (TrainingRecords.cleanup): its composed day, unless used again.
func discardCleanup(_ request: DiscardRequest) throws -> DiscardAnswer {
    let cleanup = try request.training.records().cleanup(discarding: request.sessionID)
    return DiscardAnswer(dayID: cleanup.map { lower($0.dayID) }, itemIDs: cleanup?.itemIDs.map(lower) ?? [], programID: cleanup?.programID.map(lower))
}

struct SetInput: Decodable {
    /// In the user's unit.
    let weight: Double?
    let reps: Int?
    let rpe: Double?
    let usesPounds: Bool
}

struct LoggedSetAnswer: Encodable {
    let canLog: Bool
    let weightKg: Double
    let reps: Int
    let rpe: Double?
}

/// A set as it is stored (TrainingStore.log), from what the user typed; `canLog` false without weight or reps.
func loggedSet(_ request: SetInput) -> LoggedSetAnswer {
    let unit: WeightUnit = request.usesPounds ? .pounds : .kilograms
    let set = TrainingRecords.loggedSet(weightKg: unit.kilograms(from: request.weight ?? 0), reps: request.reps ?? 0, rpe: request.rpe)
    return LoggedSetAnswer(canLog: TrainingRecords.canLog(weight: request.weight, reps: request.reps), weightKg: set.weightKg, reps: set.reps, rpe: set.rpe)
}

// MARK: Composing

struct ComposeRequest: Decodable {
    let training: TrainingInput
    let focus: TrainingFocus
    let minutes: Int
}

struct PlannedOutput: Encodable {
    let exerciseID: String
    let name: String
    let sets: Int
    let repMin: Int
    let repMax: Int
    let restSeconds: Int
}

struct PlanAnswer: Encodable {
    let exercises: [PlannedOutput]
    let minutes: Int
    let roundedMinutes: Int
    let leavesTimeOver: Bool
    let leftOut: [String]
    /// The id of the day for this workout: it tells every device that it is composed and for which focus.
    let dayID: String
    /// The programme of composed workouts the day goes in; nil when there is none yet.
    let programID: String?
}

/// The workout for a focus in the chosen time (TrainingViewModel.plan), from every exercise and the history.
func composePlan(_ request: ComposeRequest) throws -> PlanAnswer {
    let records = try request.training.records()
    let plan = WorkoutBuilder.plan(request.focus, minutes: request.minutes, from: records.workoutCandidates(), history: records.workoutHistory())
    return PlanAnswer(
        exercises: plan.exercises.map { planned in
            PlannedOutput(
                exerciseID: lower(planned.exerciseID), name: records.exercise(planned.exerciseID)?.name.text(preferring: records.languages) ?? "",
                sets: planned.sets, repMin: planned.repRange.lowerBound, repMax: planned.repRange.upperBound, restSeconds: planned.restSeconds
            )
        },
        minutes: plan.minutes, roundedMinutes: plan.roundedMinutes, leavesTimeOver: plan.leavesTimeOver, leftOut: plan.leftOut.map(\.rawValue),
        dayID: lower(ComposedWorkout.dayID(for: request.focus)), programID: records.composedProgram().map { lower($0.id) }
    )
}

struct FocusOutput: Encodable {
    let id: String
    /// The muscles it trains, to name under it.
    let muscles: [String]
}

struct DurationsAnswer: Encodable {
    let durations: [Int]
    let defaultMinutes: Int
    /// At or under this many minutes rest is shorter and there are sometimes fewer sets.
    let shortWorkoutMinutes: Int
    let focuses: [FocusOutput]
}

/// The times and focuses the composer offers.
func trainingChoices() -> DurationsAnswer {
    DurationsAnswer(
        durations: WorkoutBuilder.durations, defaultMinutes: WorkoutBuilder.defaultMinutes, shortWorkoutMinutes: WorkoutBuilder.shortWorkoutMinutes,
        focuses: TrainingFocus.allCases.map { FocusOutput(id: $0.rawValue, muscles: $0.muscles.map(\.rawValue)) }
    )
}

// MARK: Progress

struct ExerciseRequest: Decodable {
    let training: TrainingInput
    let exerciseID: UUID
}

struct PointOutput: Encodable {
    let day: String
    let kg: Double
}

struct ProgressAnswer: Encodable {
    /// The best estimated one-rep max of each workout; sets over twelve reps give none.
    let points: [PointOutput]
    let heaviestKg: Double?
    let bestOneRepMaxKg: Double?
    let workouts: Int
    let advice: AdviceOutput
    let stepKg: Double
}

/// One exercise over time (ExerciseProgressView).
func exerciseProgress(_ request: ExerciseRequest) throws -> ProgressAnswer {
    let records = try request.training.records()
    guard let exercise = records.exercise(request.exerciseID) else { throw CallError(description: "unknown exercise") }
    let history = records.history(of: exercise.id)
    let points = history.compactMap { session in
        session.sets.compactMap { ProgressionEngine.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max().map { PointOutput(day: session.day.isoString, kg: $0) }
    }
    return ProgressAnswer(
        points: points, heaviestKg: history.flatMap(\.sets).map(\.weightKg).max(), bestOneRepMaxKg: points.map(\.kg).max(), workouts: history.count,
        advice: AdviceOutput(records.adviceAfterLastWorkout(for: exercise)), stepKg: records.setting(for: exercise.id)?.stepKg ?? exercise.defaultStepKg
    )
}

struct VolumeRequest: Decodable {
    let training: TrainingInput
    let lastWeek: Bool
}

struct VolumeBar: Encodable {
    let muscle: String
    let sets: Double
}

/// Sets per muscle in this week or the last (VolumeView), in the order of the muscles.
func weeklyVolume(_ request: VolumeRequest) throws -> [VolumeBar] {
    let records = try request.training.records()
    let week = request.lastWeek ? records.today.weekStart.adding(-7) : records.today.weekStart
    let volume = records.weeklyVolume()[week] ?? [:]
    return MuscleGroup.allCases.compactMap { muscle in volume[muscle].map { VolumeBar(muscle: muscle.rawValue, sets: $0.sets) } }
}

// MARK: Body

struct MeasurementRequest: Decodable {
    let value: Double
    let kind: MeasurementKind
    let usesMetric: Bool
}

struct MeasurementAnswer: Encodable {
    let value: Double?
}

/// From the user's unit to what is stored; nil outside what the database accepts (BodyLog.storedValue).
func measurementStored(_ request: MeasurementRequest) -> MeasurementAnswer {
    MeasurementAnswer(value: BodyMeasurements.storedValue(request.value, kind: request.kind, usesMetric: request.usesMetric))
}

/// A stored value in the user's unit (BodyLog.displayValue).
func measurementShown(_ request: MeasurementRequest) -> MeasurementAnswer {
    MeasurementAnswer(value: BodyMeasurements.displayValue(request.value, kind: request.kind, usesMetric: request.usesMetric))
}
