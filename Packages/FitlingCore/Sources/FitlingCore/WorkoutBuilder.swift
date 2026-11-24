#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// What a workout made on the spot trains.
public enum TrainingFocus: String, Sendable, CaseIterable, Codable {
    case fullBody = "full_body"
    case upperBody = "upper_body"
    case lowerBody = "lower_body"
    case push, pull, arms

    /// The muscle groups the workout must train, in the order exercises are picked for them.
    public var muscles: [MuscleGroup] {
        switch self {
        case .fullBody: [.quads, .chest, .back, .hamstrings, .shoulders]
        case .upperBody: [.chest, .back, .shoulders, .biceps, .triceps]
        case .lowerBody: [.quads, .hamstrings, .glutes, .calves]
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.back, .biceps]
        case .arms: [.biceps, .triceps, .forearms]
        }
    }

    /// The muscles that get a second main exercise when there is time: a pull workout has only two muscles,
    /// and one row is no back workout.
    var secondMains: [MuscleGroup] {
        self == .pull ? [.back] : []
    }

    /// The muscle groups an exercise in this workout may train as its main work.
    var allowed: Set<MuscleGroup> {
        switch self {
        case .fullBody: Set(MuscleGroup.allCases)
        case .upperBody: Set(muscles + [.forearms])
        case .lowerBody: Set(muscles + [.core])
        case .push, .arms: Set(muscles)
        case .pull: Set(muscles + [.forearms])
        }
    }
}

/// An exercise the builder may choose, with when the user last did it.
public struct WorkoutCandidate: Sendable, Equatable {
    public var id: UUID
    public var kind: ExerciseKind
    public var primaryMuscles: [MuscleGroup]
    /// Its place in the ready-made programmes, lower is earlier. Nil when it is in none.
    public var preference: Int?
    public var lastDone: Day?

    public init(id: UUID, kind: ExerciseKind, primaryMuscles: [MuscleGroup], preference: Int? = nil, lastDone: Day? = nil) {
        self.id = id
        self.kind = kind
        self.primaryMuscles = primaryMuscles
        self.preference = preference
        self.lastDone = lastDone
    }
}

public struct PlannedExercise: Sendable, Equatable {
    public var exerciseID: UUID
    public var sets: Int
    public var repRange: ClosedRange<Int>
    public var restSeconds: Int

    public init(exerciseID: UUID, sets: Int, repRange: ClosedRange<Int>, restSeconds: Int) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.repRange = repRange
        self.restSeconds = restSeconds
    }
}

/// The workout the builder proposes, with how long it takes.
public struct WorkoutPlan: Sendable, Equatable {
    public var exercises: [PlannedExercise]
    /// The time asked for.
    public var minutes: Int
    /// The estimate, with warming up, rest and changing over.
    public var seconds: Int
    /// The muscles of the focus that did not fit, in the order of the focus.
    public var leftOut: [MuscleGroup]

    public var roundedMinutes: Int { (seconds + 59) / 60 }
    /// True when the workout is full well before the time is up.
    public var leavesTimeOver: Bool { !exercises.isEmpty && minutes * 60 - seconds >= WorkoutBuilder.timeOverSeconds }
}

/// Makes a workout for one focus in the time the user has, with the usual rules for muscle growth.
///
/// - Each muscle of the focus gets a main exercise: a compound, or for a small muscle the usual exercise for it.
///   It stays `holdWorkouts` workouts in a row, so it can get stronger, and then makes room for another. A first
///   time starts with what the ready-made programmes use.
/// - Time left goes to a third set of the mains, then to extra isolation work that varies from workout to
///   workout, then to more sets.
/// - When not every muscle fits, the one trained the longest ago goes first.
public enum WorkoutBuilder {
    /// The lengths to choose from, in minutes.
    public static let durations = [15, 20, 30, 45, 60, 75, 90]
    public static let defaultMinutes = 60
    /// Up to this many minutes a workout has shorter rest and a shorter warm-up.
    public static let shortWorkoutMinutes = 30
    public static let holdWorkouts = 8
    public static let maxExercises = 9
    public static let maxExercisesPerMuscle = 3
    public static let fewestSets = 2
    public static let usualSets = 3
    public static let mostSets = 4
    public static let compoundReps = 6...10
    public static let compoundRestSeconds = 150
    public static let shortCompoundRestSeconds = 90
    public static let isolationReps = 10...15
    public static let isolationRestSeconds = 75
    public static let shortIsolationRestSeconds = 60

    // What the estimate counts besides the rest.
    static let warmUpSeconds = 300
    static let shortWarmUpSeconds = 180
    static let changeOverSeconds = 90
    static let shortChangeOverSeconds = 60
    static let setSeconds = 45
    /// Lighter sets before the first compound, and the one before each compound after it.
    static let firstWarmUpSetsSeconds = 120
    static let warmUpSetSeconds = 60
    static let timeOverSeconds = 600

    /// These have their usual main work in isolation exercises.
    private static let smallMuscles: Set<MuscleGroup> = [.biceps, .triceps, .forearms, .calves, .core]

    private struct Slot {
        let exercise: WorkoutCandidate
        var sets: Int
        let isMain: Bool
    }

    /// `history` is the finished workouts, newest first, each with its exercises in the order they were done.
    public static func plan(_ focus: TrainingFocus, minutes: Int, from candidates: [WorkoutCandidate], history: [[UUID]]) -> WorkoutPlan {
        let usable = candidates.filter { !$0.primaryMuscles.isEmpty && Set($0.primaryMuscles).isSubset(of: focus.allowed) }
        let isShort = minutes <= shortWorkoutMinutes
        let limit = minutes * 60

        var workoutsAgo: [UUID: Int] = [:]
        for (index, workout) in history.enumerated() {
            for id in workout where workoutsAgo[id] == nil { workoutsAgo[id] = index }
        }
        var slots: [Slot] = []
        func fits(_ proposed: [Slot]) -> Bool {
            seconds(of: proposed, isShort: isShort) <= limit
        }

        // A main exercise per muscle, the muscle trained the longest ago first.
        let byMuscle = longestAgoFirst(focus.muscles, among: candidates, workoutsAgo: workoutsAgo)
        for muscle in byMuscle + focus.secondMains {
            let others = usable.filter { candidate in !slots.contains { $0.exercise.id == candidate.id } }
            guard let exercise = mainExercise(for: muscle, from: others, history: history, workoutsAgo: workoutsAgo) else { continue }
            let slot = Slot(exercise: exercise, sets: fewestSets, isMain: true)
            if fits(slots + [slot]) { slots.append(slot) }
        }

        func addSets(upTo sets: Int, where included: (Slot) -> Bool) {
            for index in slots.indices where included(slots[index]) && slots[index].sets < sets {
                var proposed = slots
                proposed[index].sets = sets
                if fits(proposed) { slots = proposed }
            }
        }
        addSets(upTo: usualSets) { $0.isMain }

        // Extra work, a round at a time along the muscles.
        let isolations = usable.filter { $0.kind == .isolation }
        let extraOrder = longestAgoFirst(focus.muscles, among: isolations, workoutsAgo: workoutsAgo)
        var added = !slots.isEmpty
        while added {
            added = false
            for muscle in extraOrder where slots.count < maxExercises {
                guard slots.filter({ $0.exercise.primaryMuscles.first == muscle }).count < maxExercisesPerMuscle else { continue }
                let open = isolations.filter { candidate in
                    candidate.primaryMuscles.first == muscle && !slots.contains { $0.exercise.id == candidate.id }
                }
                guard let exercise = freshestFirst(open, workoutsAgo: workoutsAgo).first else { continue }
                let slot = Slot(exercise: exercise, sets: fewestSets, isMain: false)
                if fits(slots + [slot]) {
                    slots.append(slot)
                    added = true
                }
            }
        }
        addSets(upTo: usualSets) { !$0.isMain }
        addSets(upTo: mostSets) { $0.isMain && $0.exercise.kind == .compound }

        let trained = Set(slots.flatMap(\.exercise.primaryMuscles))
        return WorkoutPlan(
            exercises: inOrder(slots, focus: focus).map { planned($0, isShort: isShort) },
            minutes: minutes,
            seconds: seconds(of: slots, isShort: isShort),
            leftOut: focus.muscles.filter { !trained.contains($0) }
        )
    }

    /// Another exercise of the same kind for the same main muscle, the one not done for the longest.
    public static func alternative(to exercise: WorkoutCandidate, from candidates: [WorkoutCandidate]) -> WorkoutCandidate? {
        guard let muscle = exercise.primaryMuscles.first else { return nil }
        let others = candidates.filter { $0.id != exercise.id && $0.kind == exercise.kind && $0.primaryMuscles.first == muscle }
        return others.min { first, second in
            let firstDay = first.lastDone?.ordinal ?? Int.min
            let secondDay = second.lastDone?.ordinal ?? Int.min
            if firstDay != secondDay { return firstDay < secondDay }
            return isPreferred(first, over: second)
        }
    }

    /// The one the user is on until it has had `holdWorkouts` workouts in a row, then the one not done for the
    /// longest. Workouts without any exercise for this muscle do not break the row. The first exercise of a muscle
    /// in a workout counts as its main one: `inOrder` puts the mains before the extra work.
    private static func mainExercise(
        for muscle: MuscleGroup, from candidates: [WorkoutCandidate], history: [[UUID]], workoutsAgo: [UUID: Int]
    ) -> WorkoutCandidate? {
        var pool = candidates.filter { $0.primaryMuscles.first == muscle }
        if !smallMuscles.contains(muscle) {
            let compounds = pool.filter { $0.kind == .compound }
            if !compounds.isEmpty { pool = compounds }
        }
        let ids = Set(pool.map(\.id))
        let mains = history.compactMap { workout in workout.first { ids.contains($0) } }
        guard let currentID = mains.first, let current = pool.first(where: { $0.id == currentID }) else {
            return pool.min { isPreferred($0, over: $1) }
        }
        if mains.prefix(while: { $0 == currentID }).count < holdWorkouts { return current }
        return freshestFirst(pool.filter { $0.id != currentID }, workoutsAgo: workoutsAgo).first ?? current
    }

    /// Counted in workouts, not days, so two workouts on one day still take turns.
    private static func longestAgoFirst(
        _ muscles: [MuscleGroup], among candidates: [WorkoutCandidate], workoutsAgo: [UUID: Int]
    ) -> [MuscleGroup] {
        var last: [MuscleGroup: Int] = [:]
        for candidate in candidates {
            guard let muscle = candidate.primaryMuscles.first, let ago = workoutsAgo[candidate.id] else { continue }
            last[muscle] = min(last[muscle] ?? Int.max, ago)
        }
        return muscles.enumerated().sorted { first, second in
            let firstAgo = last[first.element] ?? Int.max
            let secondAgo = last[second.element] ?? Int.max
            return firstAgo != secondAgo ? firstAgo > secondAgo : first.offset < second.offset
        }.map(\.element)
    }

    /// Never done first, then the most workouts ago.
    private static func freshestFirst(_ candidates: [WorkoutCandidate], workoutsAgo: [UUID: Int]) -> [WorkoutCandidate] {
        candidates.sorted { first, second in
            let firstAgo = workoutsAgo[first.id] ?? Int.max
            let secondAgo = workoutsAgo[second.id] ?? Int.max
            return firstAgo != secondAgo ? firstAgo > secondAgo : isPreferred(first, over: second)
        }
    }

    /// Earlier in the ready-made programmes first; the id keeps the order fixed.
    private static func isPreferred(_ first: WorkoutCandidate, over second: WorkoutCandidate) -> Bool {
        let firstPlace = first.preference ?? Int.max
        let secondPlace = second.preference ?? Int.max
        return firstPlace != secondPlace ? firstPlace < secondPlace : first.id.uuidString < second.id.uuidString
    }

    /// Compounds first, then the other mains, then the extra work; within each the order of the focus.
    private static func inOrder(_ slots: [Slot], focus: TrainingFocus) -> [Slot] {
        func key(_ entry: (offset: Int, element: Slot)) -> (Int, Int, Int) {
            let slot = entry.element
            let part = slot.exercise.kind == .compound ? 0 : (slot.isMain ? 1 : 2)
            let muscle = slot.exercise.primaryMuscles.first.flatMap { focus.muscles.firstIndex(of: $0) } ?? focus.muscles.count
            return (part, muscle, entry.offset)
        }
        return slots.enumerated().sorted { key($0) < key($1) }.map(\.element)
    }

    private static func restSeconds(_ kind: ExerciseKind, isShort: Bool) -> Int {
        switch kind {
        case .compound: isShort ? shortCompoundRestSeconds : compoundRestSeconds
        case .isolation: isShort ? shortIsolationRestSeconds : isolationRestSeconds
        }
    }

    private static func seconds(of slots: [Slot], isShort: Bool) -> Int {
        guard !slots.isEmpty else { return 0 }
        var total = isShort ? shortWarmUpSeconds : warmUpSeconds
        var hadCompound = false
        for slot in slots {
            total += isShort ? shortChangeOverSeconds : changeOverSeconds
            total += slot.sets * setSeconds + (slot.sets - 1) * restSeconds(slot.exercise.kind, isShort: isShort)
            if slot.exercise.kind == .compound {
                total += hadCompound ? warmUpSetSeconds : firstWarmUpSetsSeconds
                hadCompound = true
            }
        }
        return total
    }

    private static func planned(_ slot: Slot, isShort: Bool) -> PlannedExercise {
        let kind = slot.exercise.kind
        return PlannedExercise(
            exerciseID: slot.exercise.id, sets: slot.sets, repRange: kind == .compound ? compoundReps : isolationReps,
            restSeconds: restSeconds(kind, isShort: isShort)
        )
    }
}

extension ProgressionEngine {
    /// Sessions in a row that must stay under the best estimated one-rep max before them.
    public static let stallSessions = 4

    /// True when the last `stallSessions` sessions did not beat the best estimated one-rep max of
    /// the sessions before them: then another exercise for the same muscle is worth a try.
    public static func isStalled(history: [ExerciseSession]) -> Bool {
        let sessions = history.filter { !$0.sets.isEmpty }.sorted { $0.day < $1.day }
        guard sessions.count > stallSessions else { return false }
        func best(_ part: ArraySlice<ExerciseSession>) -> Double? {
            part.flatMap(\.sets).compactMap { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max()
        }
        guard let before = best(sessions.dropLast(stallSessions)), let recent = best(sessions.suffix(stallSessions)) else { return false }
        return recent <= before
    }
}
