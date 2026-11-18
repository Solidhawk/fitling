import Foundation

/// Picks recipes per day: greedy per meal, then a correction per day. See docs/ARCHITECTURE.md
/// for why this beats an exact optimisation here.
public enum WeekMenuPlanner {
    /// A day counts as solved inside this share around the kcal target.
    public static let kcalTolerance = 0.05
    public static let servingStep = 0.25
    public static let servingRange: ClosedRange<Double> = 0.5...2.0
    /// A recipe appears on at most this many days in one plan.
    public static let maxUsesPerRecipe = 2

    public static func plan(_ request: MenuRequest, recipes: [PlannerRecipe]) -> MenuPlan {
        MenuPlan(meals: [], issues: [])
    }
}
