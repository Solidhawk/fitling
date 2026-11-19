import Foundation

// Raw values are the exact `check` values of `food_entries.meal` and `meal_plan_entries.meal`.
public enum MealSlot: String, Sendable, CaseIterable, Codable {
    case breakfast, lunch, dinner, snack
}

/// What the planner needs to know about a recipe.
public struct PlannerRecipe: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kcalPerServing: Double
    public var proteinPerServing: Double
    public var cookMinutes: Int
    /// Nil when the price is unknown; such a recipe does not count towards the budget.
    public var costCentsPerServing: Int?
    public var slots: Set<MealSlot>
    /// What the recipe contains, such as "meat", "fish", "gluten", "nuts".
    public var tags: Set<String>
    public var ingredientIDs: Set<UUID>
    /// Suitable to cook once and eat on two days.
    public var keepsWell: Bool

    public init(
        id: UUID, kcalPerServing: Double, proteinPerServing: Double, cookMinutes: Int, costCentsPerServing: Int? = nil,
        slots: Set<MealSlot>, tags: Set<String> = [], ingredientIDs: Set<UUID> = [], keepsWell: Bool = false
    ) {
        self.id = id
        self.kcalPerServing = kcalPerServing
        self.proteinPerServing = proteinPerServing
        self.cookMinutes = cookMinutes
        self.costCentsPerServing = costCentsPerServing
        self.slots = slots
        self.tags = tags
        self.ingredientIDs = ingredientIDs
        self.keepsWell = keepsWell
    }
}

public struct PlannedMeal: Sendable, Equatable {
    public var day: Day
    public var slot: MealSlot
    public var recipeID: UUID
    public var servings: Double
    /// Cooked the day before; costs no cooking time today.
    public var isLeftover: Bool
    public var isPinned: Bool

    public init(day: Day, slot: MealSlot, recipeID: UUID, servings: Double, isLeftover: Bool = false, isPinned: Bool = false) {
        self.day = day
        self.slot = slot
        self.recipeID = recipeID
        self.servings = servings
        self.isLeftover = isLeftover
        self.isPinned = isPinned
    }
}

public struct MenuRequest: Sendable {
    public var days: [Day]
    public var kcalTarget: Int
    public var proteinTargetG: Int
    public var slots: [MealSlot]
    public var excludedIngredientIDs: Set<UUID>
    public var excludedTags: Set<String>
    /// The longest cooking time for a single recipe.
    public var maxCookMinutes: Int?
    public var budgetCents: Int?
    /// Cook dinner once, eat it on two days.
    public var mealPrep: Bool
    /// Meals the user fixed; the planner keeps them as they are.
    public var pinned: [PlannedMeal]
    /// A different seed gives a different menu from the same recipes.
    public var seed: UInt64

    public init(
        days: [Day], kcalTarget: Int, proteinTargetG: Int, slots: [MealSlot] = [.breakfast, .lunch, .dinner],
        excludedIngredientIDs: Set<UUID> = [], excludedTags: Set<String> = [], maxCookMinutes: Int? = nil,
        budgetCents: Int? = nil, mealPrep: Bool = false, pinned: [PlannedMeal] = [], seed: UInt64 = 0
    ) {
        self.days = days
        self.kcalTarget = kcalTarget
        self.proteinTargetG = proteinTargetG
        self.slots = slots
        self.excludedIngredientIDs = excludedIngredientIDs
        self.excludedTags = excludedTags
        self.maxCookMinutes = maxCookMinutes
        self.budgetCents = budgetCents
        self.mealPrep = mealPrep
        self.pinned = pinned
        self.seed = seed
    }
}

/// What the planner could not solve. The plan is still returned, so the user can adjust it.
public enum MenuIssue: Sendable, Equatable {
    case noRecipes(slot: MealSlot)
    case kcalOutOfRange(day: Day, kcal: Int)
    case proteinShort(day: Day, missingG: Int)
    case overBudget(byCents: Int)
}

public struct MenuPlan: Sendable, Equatable {
    public var meals: [PlannedMeal]
    public var issues: [MenuIssue]

    public init(meals: [PlannedMeal], issues: [MenuIssue]) {
        self.meals = meals
        self.issues = issues
    }
}
