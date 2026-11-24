#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

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
        let sessions = history.filter { !$0.sets.isEmpty }.sorted { $0.day < $1.day }
        guard let last = sessions.last, let weight = workingWeight(of: last) else { return .findStartingWeight }
        let unloadedBodyWeight = rules.loadType == .bodyweight && weight <= 0

        let daysAway = today.ordinal - last.day.ordinal
        if daysAway >= shortBreakDays {
            let share = daysAway >= longBreakDays ? longBreakReduceShare : reduceShare
            let lighter = lowered(weight, by: share, rules: rules)
            return unloadedBodyWeight || lighter == nil ? .keepGoing(weightKg: weight) : .easeBackIn(toKg: lighter ?? weight)
        }

        if sessions.count >= 2 {
            let previous = sessions[sessions.count - 2]
            // Two sessions with a break in between are not "in a row": the break explains the dip.
            let inARow = last.day.ordinal - previous.day.ordinal < shortBreakDays
            if inARow, isUnderRange(last, rules: rules), isUnderRange(previous, rules: rules) {
                if unloadedBodyWeight { return .makeEasier }
                guard let lighter = lowered(weight, by: reduceShare, rules: rules) else { return .keepGoing(weightKg: weight) }
                return .reduce(toKg: lighter)
            }
        }

        let topSets = last.sets.filter { $0.weightKg == weight }
        let top = rules.repRange.upperBound
        let everySetAtTheTop = topSets.count >= rules.targetSets
            && topSets.allSatisfy { $0.reps >= top && ($0.rpe ?? 0) <= easyEnoughRPE }
        guard everySetAtTheTop else { return .keepGoing(weightKg: weight) }
        if unloadedBodyWeight { return .makeHarder }

        let increase = smallestIncrease(for: rules)
        // For body-weight exercises the added load is only part of what is lifted, so its
        // share says nothing about the size of the jump.
        if rules.loadType == .external, increase > weight * bigJumpShare {
            let targetReps = top + extraRepsBeforeBigJump
            guard topSets.allSatisfy({ $0.reps >= targetReps }) else {
                return .addRepsFirst(weightKg: weight, targetReps: targetReps)
            }
        }
        return .increase(toKg: weight + increase)
    }

    /// Epley: weight × (1 + reps / 30). Nil outside 1...`maxRepsForOneRepMax` reps.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...maxRepsForOneRepMax).contains(reps) else { return nil }
        // Written as one division so that whole results, such as 60 kg × 12, stay exact.
        return reps == 1 ? weightKg : weightKg * Double(30 + reps) / 30
    }

    /// Records set in `session` compared with everything before it. A first session sets the
    /// baseline and returns none.
    public static func personalRecords(in session: ExerciseSession, history: [ExerciseSession]) -> [PersonalRecord] {
        let past = history.flatMap(\.sets).filter { $0.reps > 0 }
        let new = session.sets.filter { $0.reps > 0 }
        guard !past.isEmpty, !new.isEmpty else { return [] }
        var records: [PersonalRecord] = []

        if let heaviest = new.map(\.weightKg).max(), let pastHeaviest = past.map(\.weightKg).max(), heaviest > pastHeaviest {
            records.append(.weight(kg: heaviest))
        }

        let pastBest = past.compactMap { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max()
        let newBest = new.compactMap { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max()
        if let pastBest, let newBest, newBest > pastBest {
            records.append(.estimatedOneRepMax(kg: newBest))
        }

        for weight in Set(new.map(\.weightKg)).sorted(by: >) {
            let reps = new.filter { $0.weightKg == weight }.map(\.reps).max() ?? 0
            // A weight that was never used before has no rep record to beat.
            guard let pastReps = past.filter({ $0.weightKg == weight }).map(\.reps).max(), reps > pastReps else { continue }
            records.append(.reps(count: reps, atKg: weight))
        }
        return records
    }

    /// Volume per muscle group per week, keyed by the Monday of the week.
    public static func weeklyVolume(_ exercises: [LoggedExercise]) -> [Day: [MuscleGroup: MuscleVolume]] {
        var result: [Day: [MuscleGroup: MuscleVolume]] = [:]
        for exercise in exercises {
            let sets = exercise.sets.filter { $0.reps > 0 }
            guard !sets.isEmpty else { continue }
            let count = Double(sets.count)
            let tonnage = sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
            let week = exercise.day.weekStart
            let primary = Set(exercise.primaryMuscles)
            for muscle in primary {
                result[week, default: [:]][muscle, default: MuscleVolume()].sets += count
                result[week, default: [:]][muscle, default: MuscleVolume()].tonnageKg += tonnage
            }
            for muscle in Set(exercise.secondaryMuscles).subtracting(primary) {
                result[week, default: [:]][muscle, default: MuscleVolume()].sets += count / 2
                result[week, default: [:]][muscle, default: MuscleVolume()].tonnageKg += tonnage / 2
            }
        }
        return result
    }

    // MARK: Helpers

    /// The heaviest weight of the session. Lighter back-off sets after it do not count.
    private static func workingWeight(of session: ExerciseSession) -> Double? {
        session.sets.map(\.weightKg).max()
    }

    /// Under the range when more than half of the sets at the working weight miss the low end.
    private static func isUnderRange(_ session: ExerciseSession, rules: ExerciseRules) -> Bool {
        guard let weight = workingWeight(of: session) else { return false }
        let sets = session.sets.filter { $0.weightKg == weight }
        let short = sets.filter { $0.reps < rules.repRange.lowerBound }.count
        return short * 2 > sets.count
    }

    /// The smallest number of whole steps that adds at least the wanted increase.
    private static func smallestIncrease(for rules: ExerciseRules) -> Double {
        let wanted = rules.kind == .compound ? compoundIncreaseKg : isolationIncreaseKg
        guard rules.stepKg > 0 else { return wanted }
        let steps = max(1, (wanted / rules.stepKg - 1e-9).rounded(.up))
        return steps * rules.stepKg
    }

    /// `weight` minus `share`, rounded down to a weight the equipment has and always at least
    /// one step lighter. Nil when nothing lighter exists.
    private static func lowered(_ weight: Double, by share: Double, rules: ExerciseRules) -> Double? {
        let step = rules.stepKg > 0 ? rules.stepKg : 1
        var lighter = ((weight * (1 - share)) / step + 1e-9).rounded(.down) * step
        if lighter >= weight { lighter = weight - step }
        lighter = max(0, lighter)
        // An external load of nothing is no exercise; a body-weight exercise can drop its extra load.
        if lighter <= 0, rules.loadType == .external { return nil }
        return lighter < weight ? lighter : nil
    }
}
