/// One food entry as the partner sees it: the day and what it added.
public struct LoggedEntry: Sendable, Equatable {
    public var day: Day
    public var kcal: Double
    /// Nil when the product did not say; counts as 0.
    public var proteinG: Double?

    public init(day: Day, kcal: Double, proteinG: Double?) {
        self.day = day
        self.kcal = kcal
        self.proteinG = proteinG
    }
}

/// The days the partner is judged on, shared by the app and the web (D-24).
public enum DayRecords {
    /// One record per day with food logged or a workout done, in order, each day compared with the target that
    /// applied on it. Kcal and protein are summed and rounded to whole numbers.
    public static func build(entries: [LoggedEntry], workoutDays: Set<Day>, targets: (Day) -> NutritionTargets) -> [DayRecord] {
        let byDay = Dictionary(grouping: entries, by: \.day)
        return Set(byDay.keys).union(workoutDays).sorted().map { day in
            let logged = byDay[day] ?? []
            let target = targets(day)
            return DayRecord(
                day: day,
                kcal: Int(logged.reduce(0) { $0 + $1.kcal }.rounded()),
                kcalTarget: target.kcal,
                proteinG: Int(logged.reduce(0) { $0 + ($1.proteinG ?? 0) }.rounded()),
                proteinTargetG: target.proteinG,
                entryCount: logged.count,
                workoutCompleted: workoutDays.contains(day)
            )
        }
    }
}
