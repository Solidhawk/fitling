import Foundation

/// Double progression: first more reps inside the range, then more weight.
public enum ProgressionEngine {
    public static let easyEnoughRPE = 8.0
    public static let compoundIncreaseKg = 2.5
    public static let isolationIncreaseKg = 1.0
    /// A step of more than this share of the current weight counts as a big jump.
    public static let bigJumpShare = 0.10
    public static let extraRepsBeforeBigJump = 2
    public static let reduceShare = 0.10
    public static let shortBreakDays = 14
    public static let longBreakDays = 28
    public static let longBreakReduceShare = 0.20
    /// Epley is not reliable for long sets.
    public static let maxRepsForOneRepMax = 12

    public static func advise(history: [ExerciseSession], rules: ExerciseRules, today: Day) -> ProgressionAdvice {
        .findStartingWeight
    }

    /// Epley: weight × (1 + reps / 30). Nil outside 1...`maxRepsForOneRepMax` reps.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        nil
    }

    /// Records set in `session` compared with everything before it. A first session sets the
    /// baseline and returns none.
    public static func personalRecords(in session: ExerciseSession, history: [ExerciseSession]) -> [PersonalRecord] {
        []
    }

    /// Volume per muscle group per week, keyed by the Monday of the week.
    public static func weeklyVolume(_ exercises: [LoggedExercise]) -> [Day: [MuscleGroup: MuscleVolume]] {
        [:]
    }
}
