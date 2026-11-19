import Foundation
import Observation
import FitlingCore

/// Kilograms or pounds, by the user's region. The store always holds kilograms.
enum WeightUnit: Equatable {
    case kilograms, pounds

    static let kilogramsPerPound = 0.45359237

    init(locale: Locale) {
        self = locale.measurementSystem == .us ? .pounds : .kilograms
    }

    func kilograms(from value: Double) -> Double {
        self == .pounds ? value * Self.kilogramsPerPound : value
    }

    func value(fromKilograms kilograms: Double) -> Double {
        self == .pounds ? kilograms / Self.kilogramsPerPound : kilograms
    }

    var symbol: String {
        self == .pounds ? UnitMass.pounds.symbol : UnitMass.kilograms.symbol
    }

    /// "62,5 kg" in the user's own number format.
    func format(kilograms: Double) -> String {
        let value = self.value(fromKilograms: kilograms)
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(symbol)"
    }
}

/// One workout: the exercises of the programme day (and any the user adds), the sets logged so
/// far, the advice per exercise and the rest timer.
@Observable
@MainActor
final class WorkoutViewModel {
    struct Entry: Identifiable {
        let exercise: Exercise
        /// Nil for an exercise added during the workout.
        let item: ProgramExercise?
        var id: UUID { item?.id ?? exercise.id }
    }

    /// What the user is about to log for one exercise, in their own unit.
    struct Draft: Equatable {
        var weight: Double?
        var reps: Int?
        var rpe: Double?
        var isWarmup = false
    }

    static let defaultRestSeconds = 120

    let session: WorkoutSession
    let unit: WeightUnit
    private(set) var entries: [Entry] = []
    private(set) var sets: [WorkoutSet] = []
    var drafts: [UUID: Draft] = [:]
    /// When the rest after the last working set is over. Nil when no rest is running.
    private(set) var restEndsAt: Date?
    private(set) var isFinished = false

    private let store: TrainingStore

    init(session: WorkoutSession, store: TrainingStore, unit: WeightUnit = WeightUnit(locale: .current)) {
        self.session = session
        self.store = store
        self.unit = unit
        if let dayID = session.programDayID, let day = store.day(dayID) {
            entries = store.items(of: day).compactMap { item in store.exercise(item.exerciseID).map { Entry(exercise: $0, item: item) } }
        }
        reload()
        // Exercises logged on another device or before a restart, which are not in the programme day.
        for set in sets where !entries.contains(where: { $0.exercise.id == set.exerciseID }) {
            if let exercise = store.exercise(set.exerciseID) { entries.append(Entry(exercise: exercise, item: nil)) }
        }
        for entry in entries where drafts[entry.id] == nil {
            prefill(entry)
        }
    }

    /// For picking an exercise to add.
    var exerciseStore: TrainingStore {
        store
    }

    var title: LocalizedText? {
        guard let dayID = session.programDayID else { return nil }
        return store.day(dayID)?.name
    }

    func reload() {
        sets = store.sets(of: session)
    }

    func sets(of entry: Entry) -> [WorkoutSet] {
        sets.filter { $0.exerciseID == entry.exercise.id }
    }

    func advice(for entry: Entry) -> ProgressionAdvice {
        store.advice(for: entry.exercise, in: entry.item, excluding: session)
    }

    func rules(for entry: Entry) -> ExerciseRules {
        store.rules(for: entry.exercise, in: entry.item)
    }

    /// Fills in the next set from the advice: the weight it names and the reps to aim for.
    func prefill(_ entry: Entry) {
        let rules = self.rules(for: entry)
        var draft = drafts[entry.id] ?? Draft()
        draft.reps = rules.repRange.lowerBound
        switch advice(for: entry) {
        case let .increase(weight), let .reduce(weight), let .easeBackIn(weight):
            draft.weight = rounded(unit.value(fromKilograms: weight))
        case let .keepGoing(weight):
            draft.weight = rounded(unit.value(fromKilograms: weight))
            // Aim for one more rep than last time at this weight, up to the top of the range.
            let last = store.history(of: entry.exercise.id, excluding: session).last?.sets.filter { $0.weightKg == weight }.map(\.reps).max()
            draft.reps = min(max((last ?? rules.repRange.lowerBound - 1) + 1, rules.repRange.lowerBound), rules.repRange.upperBound)
        case let .addRepsFirst(weight, targetReps):
            draft.weight = rounded(unit.value(fromKilograms: weight))
            draft.reps = targetReps
        case .findStartingWeight, .makeHarder, .makeEasier:
            break
        }
        drafts[entry.id] = draft
    }

    func canLog(_ entry: Entry) -> Bool {
        guard let draft = drafts[entry.id], let weight = draft.weight, let reps = draft.reps else { return false }
        return weight >= 0 && reps > 0
    }

    /// Stores the draft as a set. A working set starts the rest timer; a warm-up set does not.
    @discardableResult
    func log(_ entry: Entry) -> WorkoutSet? {
        guard canLog(entry), let draft = drafts[entry.id], let weight = draft.weight, let reps = draft.reps else { return nil }
        let set = store.log(
            in: session, exercise: entry.exercise, weightKg: unit.kilograms(from: weight), reps: reps, rpe: draft.rpe, isWarmup: draft.isWarmup
        )
        reload()
        if !draft.isWarmup {
            restEndsAt = store.now().addingTimeInterval(TimeInterval(entry.item?.restSeconds ?? Self.defaultRestSeconds))
        }
        // The next set starts like the one just done; RPE is asked again.
        drafts[entry.id]?.rpe = nil
        return set
    }

    func skipRest() {
        restEndsAt = nil
    }

    func remove(_ set: WorkoutSet) {
        store.remove(set)
        reload()
    }

    func add(_ exercise: Exercise) {
        guard !entries.contains(where: { $0.exercise.id == exercise.id }) else { return }
        let entry = Entry(exercise: exercise, item: nil)
        entries.append(entry)
        prefill(entry)
    }

    func finish() {
        store.finish(session)
        restEndsAt = nil
        isFinished = true
    }

    func discard() {
        store.discard(session)
        restEndsAt = nil
        isFinished = true
    }

    /// Records set in this workout, to celebrate at the end.
    func records() -> [(Exercise, PersonalRecord)] {
        entries.flatMap { entry -> [(Exercise, PersonalRecord)] in
            let working = sets(of: entry).compactMap(\.workingSet)
            guard !working.isEmpty else { return [] }
            let session = ExerciseSession(day: store.today, sets: working)
            return ProgressionEngine.personalRecords(in: session, history: store.history(of: entry.exercise.id, excluding: self.session))
                .map { (entry.exercise, $0) }
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
