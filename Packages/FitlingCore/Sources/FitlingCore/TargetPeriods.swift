#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A period of daily targets: from `effectiveOn` until the next period starts (table `target_history`).
public struct TargetPeriodRecord: Sendable, Equatable {
    public let effectiveOn: Day
    public let updatedAt: Date
    public let targets: NutritionTargets

    public init(effectiveOn: Day, updatedAt: Date, targets: NutritionTargets) {
        self.effectiveOn = effectiveOn
        self.updatedAt = updatedAt
        self.targets = targets
    }
}

/// Which daily target held on a day, so a day is always compared with the target of that day (ARCHITECTURE §7).
public enum TargetPeriods {
    /// The latest period that started on or before `day`; of two on the same day the newest change, as when two
    /// devices each made one. Before every period the profile's own targets hold.
    public static func targets(on day: Day, periods: [TargetPeriodRecord], fallback: NutritionTargets) -> NutritionTargets {
        periods
            .filter { $0.effectiveOn <= day }
            .max { ($0.effectiveOn, $0.updatedAt) < ($1.effectiveOn, $1.updatedAt) }?
            .targets ?? fallback
    }
}
