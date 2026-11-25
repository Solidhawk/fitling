#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

// The recipes and week menu of one user, and what the app and the web read and decide from them: the order of
// recipes and meals, which recipes fit a meal, what a new menu or a renewed day keeps and adds, and what a meal
// logged with one tap holds. The app builds this from SwiftData, the web from Supabase; both write their own rows.
// Only rows that are not deleted.

/// A shared recipe or one of the user's own, with the products in it (for what the user leaves out).
public struct MenuRecipe: Sendable, Equatable, Codable {
    public var id: UUID
    public var ownerID: UUID?
    public var title: LocalizedText
    public var servings: Int
    public var cookMinutes: Int
    public var kcalPerServing: Double
    public var proteinGPerServing: Double
    public var carbsGPerServing: Double
    public var fatGPerServing: Double
    public var costCentsPerServing: Int?
    public var keepsWell: Bool
    public var mealSlots: [String]
    public var tags: [String]
    public var productIDs: [UUID]

    public init(
        id: UUID, ownerID: UUID?, title: LocalizedText, servings: Int, cookMinutes: Int, kcalPerServing: Double,
        proteinGPerServing: Double, carbsGPerServing: Double, fatGPerServing: Double, costCentsPerServing: Int? = nil,
        keepsWell: Bool = false, mealSlots: [String], tags: [String] = [], productIDs: [UUID] = []
    ) {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.servings = servings
        self.cookMinutes = cookMinutes
        self.kcalPerServing = kcalPerServing
        self.proteinGPerServing = proteinGPerServing
        self.carbsGPerServing = carbsGPerServing
        self.fatGPerServing = fatGPerServing
        self.costCentsPerServing = costCentsPerServing
        self.keepsWell = keepsWell
        self.mealSlots = mealSlots
        self.tags = tags
        self.productIDs = productIDs
    }

    /// The recipe as the week-menu planner sees it. Nil for a recipe without energy, which the planner could not scale.
    public var plannerRecipe: PlannerRecipe? {
        guard kcalPerServing > 0 else { return nil }
        return PlannerRecipe(
            id: id, kcalPerServing: kcalPerServing, proteinPerServing: proteinGPerServing, cookMinutes: cookMinutes,
            costCentsPerServing: costCentsPerServing, slots: Set(mealSlots.compactMap(MealSlot.init(rawValue:))),
            tags: Set(tags), ingredientIDs: Set(productIDs), keepsWell: keepsWell
        )
    }
}

/// One planned meal of the week menu.
public struct MenuEntry: Sendable, Equatable, Codable {
    public var id: UUID
    public var plannedOn: Day
    public var meal: String
    public var recipeID: UUID
    public var servings: Double
    public var isLeftover: Bool
    public var isPinned: Bool
    public var loggedEntryID: UUID?

    public init(
        id: UUID, plannedOn: Day, meal: String, recipeID: UUID, servings: Double, isLeftover: Bool = false, isPinned: Bool = false,
        loggedEntryID: UUID? = nil
    ) {
        self.id = id
        self.plannedOn = plannedOn
        self.meal = meal
        self.recipeID = recipeID
        self.servings = servings
        self.isLeftover = isLeftover
        self.isPinned = isPinned
        self.loggedEntryID = loggedEntryID
    }

    /// Nil when the stored meal is not one this version knows.
    public var plannedMeal: PlannedMeal? {
        MealSlot(rawValue: meal).map { PlannedMeal(day: plannedOn, slot: $0, recipeID: recipeID, servings: servings, isLeftover: isLeftover, isPinned: isPinned) }
    }
}

/// What the user wants in a menu (`menu_preferences`).
public struct MenuSettings: Sendable, Equatable, Codable {
    public var excludedTags: [String]
    public var maxCookMinutes: Int?
    public var budgetCents: Int?
    public var mealPrep: Bool
    public var mealSlots: [String]

    public init(excludedTags: [String] = [], maxCookMinutes: Int? = nil, budgetCents: Int? = nil, mealPrep: Bool = false, mealSlots: [String] = ["breakfast", "lunch", "dinner"]) {
        self.excludedTags = excludedTags
        self.maxCookMinutes = maxCookMinutes
        self.budgetCents = budgetCents
        self.mealPrep = mealPrep
        self.mealSlots = mealSlots
    }
}

/// What a new menu or a renewed day changes: the meals that go, those that come, and what the planner could not solve.
public struct MenuChange: Sendable, Equatable {
    public var removed: [UUID]
    public var added: [PlannedMeal]
    public var issues: [MenuIssue]
}

/// A planned meal logged with one tap: one food entry with the recipe's values for the planned servings.
public struct LoggedMeal: Sendable, Equatable {
    public var recipeID: UUID
    public var name: String
    public var day: Day
    public var slot: MealSlot
    public var servings: Double
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
}

public struct MenuBook: Sendable {
    /// Today and the six days after it.
    public static let menuDays = 7

    public let userID: UUID
    public let today: Day
    public let languages: [String]
    public let settings: MenuSettings
    private let recipeRows: [MenuRecipe]
    private let entryRows: [MenuEntry]
    private let excludedProductIDs: Set<UUID>

    public init(
        userID: UUID, recipes: [MenuRecipe], entries: [MenuEntry], settings: MenuSettings, excludedProductIDs: Set<UUID>, today: Day,
        languages: [String]
    ) {
        self.userID = userID
        recipeRows = recipes.filter { $0.ownerID == nil || $0.ownerID == userID }
        entryRows = entries
        self.settings = settings
        self.excludedProductIDs = excludedProductIDs
        self.today = today
        self.languages = languages
    }

    public var menuDays: [Day] {
        (0..<Self.menuDays).map { today.adding($0) }
    }

    /// Shared and own recipes, by title in the user's language.
    public func recipes() -> [MenuRecipe] {
        recipeRows.sorted { TrainingRecords.inOrder($0.title.text(preferring: languages), $1.title.text(preferring: languages)) }
    }

    public func recipe(_ id: UUID) -> MenuRecipe? {
        recipeRows.first { $0.id == id }
    }

    /// The week menu from today, by day and in the order of the meals.
    public func entries() -> [MenuEntry] {
        let last = today.adding(Self.menuDays - 1)
        let slotOrder = Dictionary(uniqueKeysWithValues: MealSlot.allCases.enumerated().map { ($1.rawValue, $0) })
        return entryRows
            .filter { $0.plannedOn >= today && $0.plannedOn <= last }
            .sorted { ($0.plannedOn, slotOrder[$0.meal] ?? 9) < ($1.plannedOn, slotOrder[$1.meal] ?? 9) }
    }

    /// Recipes that fit this meal, for swapping: the same meal, another recipe.
    public func recipes(for entryID: UUID) -> [MenuRecipe] {
        guard let entry = entryRows.first(where: { $0.id == entryID }) else { return [] }
        return recipes().filter { $0.mealSlots.contains(entry.meal) && $0.id != entry.recipeID }
    }

    /// A new menu from today for `days` days. Pinned and already logged meals stay; the rest is replaced. A different
    /// `seed` gives a different menu from the same recipes.
    public func generate(days: Int, seed: UInt64, targets: NutritionTargets) -> MenuChange {
        let count = min(max(days, 1), Self.menuDays)
        return plan(days: (0..<count).map { today.adding($0) }, replacing: entries(), seed: seed, targets: targets)
    }

    /// New meals for one day; the other days stay as they are.
    public func renew(_ day: Day, seed: UInt64, targets: NutritionTargets) -> MenuChange {
        plan(days: [day], replacing: entries().filter { $0.plannedOn == day }, seed: seed, targets: targets)
    }

    private func plan(days: [Day], replacing existing: [MenuEntry], seed: UInt64, targets: NutritionTargets) -> MenuChange {
        let kept = existing.filter { $0.isPinned || $0.loggedEntryID != nil }
        let request = MenuRequest(
            days: days, kcalTarget: targets.kcal, proteinTargetG: targets.proteinG,
            slots: settings.mealSlots.compactMap(MealSlot.init(rawValue:)), excludedIngredientIDs: excludedProductIDs,
            excludedTags: Set(settings.excludedTags), maxCookMinutes: settings.maxCookMinutes, budgetCents: settings.budgetCents,
            mealPrep: settings.mealPrep,
            pinned: kept.compactMap(\.plannedMeal).map { meal in
                var meal = meal
                meal.isPinned = true
                return meal
            },
            seed: seed
        )
        let plan = WeekMenuPlanner.plan(request, recipes: recipes().compactMap(\.plannerRecipe))
        let keptIDs = Set(kept.map(\.id))
        let keptSlots = Set(kept.map { "\($0.plannedOn.isoString)|\($0.meal)" })
        return MenuChange(
            removed: existing.filter { !keptIDs.contains($0.id) }.map(\.id),
            added: plan.meals.filter { !keptSlots.contains("\($0.day.isoString)|\($0.slot.rawValue)") }.map { meal in
                var meal = meal
                meal.isPinned = false
                return meal
            },
            issues: plan.issues
        )
    }

    /// A planned meal logged with one tap: the recipe's values for the planned servings, to the tenth. Nil for a meal
    /// already logged or whose recipe is gone; a second tap does nothing.
    public func loggedMeal(_ entryID: UUID) -> LoggedMeal? {
        guard let entry = entryRows.first(where: { $0.id == entryID }), entry.loggedEntryID == nil, let recipe = recipe(entry.recipeID),
              let slot = MealSlot(rawValue: entry.meal) else { return nil }
        let tenth = { (value: Double) in (value * entry.servings * 10).rounded() / 10 }
        return LoggedMeal(
            recipeID: recipe.id, name: recipe.title.text(preferring: languages), day: entry.plannedOn, slot: slot, servings: entry.servings,
            kcal: tenth(recipe.kcalPerServing), proteinG: tenth(recipe.proteinGPerServing), carbsG: tenth(recipe.carbsGPerServing),
            fatG: tenth(recipe.fatGPerServing)
        )
    }

    /// Whether a recipe of the user's own can be kept: a title, at least one meal, and servings, time and values within
    /// what the `recipes` table accepts (MenuStore.OwnRecipe.isComplete).
    public static func ownRecipeIsComplete(
        title: String, servings: Int, cookMinutes: Int, kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, mealSlots: [String]
    ) -> Bool {
        guard let kcal, let protein, let carbs, let fat else { return false }
        return !title.trimmingWhitespace().isEmpty && !mealSlots.isEmpty && (1...20).contains(servings) && (0...600).contains(cookMinutes)
            && (0...5000).contains(kcal) && (0...500).contains(protein) && (0...1000).contains(carbs) && (0...500).contains(fat)
    }
}
