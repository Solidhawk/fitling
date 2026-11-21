import Foundation

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
    public var lastDone: Day?

    public init(id: UUID, kind: ExerciseKind, primaryMuscles: [MuscleGroup], lastDone: Day? = nil) {
        self.id = id
        self.kind = kind
        self.primaryMuscles = primaryMuscles
        self.lastDone = lastDone
    }
}

public struct PlannedExercise: Sendable, Equatable {
    public var exerciseID: UUID
    public var sets: Int
    public var repRange: ClosedRange<Int>
    public var restSeconds: Int
}

/// Makes a workout for one focus with the usual rules for muscle growth: compound exercises first
/// and in the 6–10 range with long rests, then isolation exercises at 10–15 with short rests, three
/// working sets each, every target muscle trained directly. Exercises the user has not done for the
/// longest come first, so the workouts vary.
public enum WorkoutBuilder {
    public static let maxExercises = 6
    public static let minExercises = 4
    public static let compoundSets = 3
    public static let compoundReps = 6...10
    public static let compoundRestSeconds = 150
    public static let isolationSets = 3
    public static let isolationReps = 10...15
    public static let isolationRestSeconds = 75

    public static func build(_ focus: TrainingFocus, from candidates: [WorkoutCandidate]) -> [PlannedExercise] {
        let usable = candidates.filter { !$0.primaryMuscles.isEmpty && Set($0.primaryMuscles).isSubset(of: focus.allowed) }
        let target = min(max(focus.muscles.count + 1, minExercises), maxExercises)
        var chosen: [WorkoutCandidate] = []
        var covered = Set<MuscleGroup>()

        func pick(for muscle: MuscleGroup, kind: ExerciseKind?) -> WorkoutCandidate? {
            freshestFirst(usable.filter { candidate in
                candidate.primaryMuscles.contains(muscle)
                    && (kind == nil || candidate.kind == kind)
                    && !chosen.contains { $0.id == candidate.id }
            }).first
        }

        func add(_ candidate: WorkoutCandidate?) {
            guard let candidate, chosen.count < maxExercises else { return }
            chosen.append(candidate)
            covered.formUnion(candidate.primaryMuscles)
        }

        // A compound per target muscle, then whatever trains the muscles still missing, then more
        // isolation work in the order of the targets until the workout is long enough.
        for muscle in focus.muscles where !covered.contains(muscle) {
            add(pick(for: muscle, kind: .compound))
        }
        for muscle in focus.muscles where !covered.contains(muscle) {
            add(pick(for: muscle, kind: .isolation) ?? pick(for: muscle, kind: nil))
        }
        for muscle in focus.muscles where chosen.count < target {
            add(pick(for: muscle, kind: .isolation))
        }

        let ordered = chosen.filter { $0.kind == .compound } + chosen.filter { $0.kind == .isolation }
        return ordered.map { candidate in
            candidate.kind == .compound
                ? PlannedExercise(exerciseID: candidate.id, sets: compoundSets, repRange: compoundReps, restSeconds: compoundRestSeconds)
                : PlannedExercise(exerciseID: candidate.id, sets: isolationSets, repRange: isolationReps, restSeconds: isolationRestSeconds)
        }
    }

    /// Another exercise of the same kind for the same main muscle, the one not done for the longest.
    public static func alternative(to exercise: WorkoutCandidate, from candidates: [WorkoutCandidate]) -> WorkoutCandidate? {
        guard let muscle = exercise.primaryMuscles.first else { return nil }
        return freshestFirst(candidates.filter {
            $0.id != exercise.id && $0.kind == exercise.kind && $0.primaryMuscles.first == muscle
        }).first
    }

    /// Never done first, then the longest ago; the id keeps the order fixed.
    private static func freshestFirst(_ candidates: [WorkoutCandidate]) -> [WorkoutCandidate] {
        candidates.sorted { first, second in
            let firstDay = first.lastDone?.ordinal ?? Int.min
            let secondDay = second.lastDone?.ordinal ?? Int.min
            if firstDay != secondDay { return firstDay < secondDay }
            return first.id.uuidString < second.id.uuidString
        }
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
