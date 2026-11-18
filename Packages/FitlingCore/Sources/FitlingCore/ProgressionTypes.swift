import Foundation

// Raw values are the exact `check` values of the `exercises` table in Supabase.
public enum ExerciseKind: String, Sendable, CaseIterable, Codable {
    case compound, isolation
}

public enum LoadType: String, Sendable, CaseIterable, Codable {
    /// Barbell, dumbbell, machine, cable: `weightKg` is the whole load.
    case external
    /// Push-ups, pull-ups, dips: `weightKg` is only what is added to the body, 0 for none.
    case bodyweight
}

public enum MuscleGroup: String, Sendable, CaseIterable, Codable {
    case chest, back, shoulders, biceps, triceps, forearms, core, glutes, quads, hamstrings, calves
}

/// How one exercise progresses for one user.
public struct ExerciseRules: Sendable, Equatable {
    public var kind: ExerciseKind
    public var loadType: LoadType
    public var repRange: ClosedRange<Int>
    public var targetSets: Int
    /// The smallest weight change the user's equipment allows: 2.5 for a barbell with 1.25 kg
    /// plates, 2 for dumbbells that go up per 2 kg, 5 for a machine stack.
    public var stepKg: Double

    public init(kind: ExerciseKind, loadType: LoadType = .external, repRange: ClosedRange<Int>, targetSets: Int, stepKg: Double) {
        self.kind = kind
        self.loadType = loadType
        self.repRange = repRange
        self.targetSets = targetSets
        self.stepKg = stepKg
    }
}

/// A set that counts. Warm-up sets are left out by the caller.
public struct WorkingSet: Sendable, Equatable {
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?

    public init(weightKg: Double, reps: Int, rpe: Double? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
    }
}

/// The working sets of one exercise in one workout.
public struct ExerciseSession: Sendable, Equatable {
    public var day: Day
    public var sets: [WorkingSet]

    public init(day: Day, sets: [WorkingSet]) {
        self.day = day
        self.sets = sets
    }
}

public enum ProgressionAdvice: Sendable, Equatable {
    /// No history: start with a weight that gives the low end of the range at RPE 8 or less.
    case findStartingWeight
    /// Stay at this weight and work towards the top of the range.
    case keepGoing(weightKg: Double)
    case increase(toKg: Double)
    /// The next weight is a big jump for this equipment: first reach `targetReps` on every set.
    case addRepsFirst(weightKg: Double, targetReps: Int)
    case reduce(toKg: Double)
    /// Back after two weeks or more without this exercise.
    case easeBackIn(toKg: Double)
    /// Body-weight exercise at the top of the range without added load: add weight or pick a
    /// harder variation.
    case makeHarder
    /// Body-weight exercise under the range without added load: pick an easier variation.
    case makeEasier
}

public enum PersonalRecord: Sendable, Equatable {
    case weight(kg: Double)
    case estimatedOneRepMax(kg: Double)
    case reps(count: Int, atKg: Double)
}

public struct LoggedExercise: Sendable, Equatable {
    public var day: Day
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var sets: [WorkingSet]

    public init(day: Day, primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup] = [], sets: [WorkingSet]) {
        self.day = day
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.sets = sets
    }
}

public struct MuscleVolume: Sendable, Equatable {
    /// Hard sets: a set counts fully for a primary muscle and half for a secondary one.
    public var sets: Double
    public var tonnageKg: Double

    public init(sets: Double = 0, tonnageKg: Double = 0) {
        self.sets = sets
        self.tonnageKg = tonnageKg
    }
}
