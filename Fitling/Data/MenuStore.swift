import Foundation
import SwiftData
import FitlingCore

/// Recipes, menu preferences and the week menu of one user (TASKS 5.2–5.5).
@MainActor
struct MenuStore {
    static let menuDays = 7

    let context: ModelContext
    let profile: UserProfile
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init
    var language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "nl"

    var userID: UUID { profile.id }

    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    /// Today and the six days after it.
    var menuDays: [Day] {
        (0..<Self.menuDays).map { today.adding($0) }
    }

    // MARK: Recipes

    /// Shared and own recipes, by title in the user's language.
    func recipes() -> [Recipe] {
        let owner: UUID? = userID
        let all = (try? context.fetch(FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
        let languages = Locale.preferredLanguages
        return all.sorted { $0.title.text(preferring: languages).localizedStandardCompare($1.title.text(preferring: languages)) == .orderedAscending }
    }

    func recipe(_ id: UUID) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func ingredients(of recipe: Recipe) -> [RecipeIngredient] {
        let recipeID = recipe.id
        return (try? context.fetch(FetchDescriptor<RecipeIngredient>(
            predicate: #Predicate<RecipeIngredient> { $0.recipeID == recipeID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        ))) ?? []
    }

    /// A recipe of the user's own. Its energy and macros are the user's own numbers per serving.
    struct OwnRecipe {
        var title = ""
        var servings = 2
        var cookMinutes = 30
        var kcal: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var slots: Set<MealSlot> = [.dinner]
        var ingredients: [(name: String, quantity: Double, unit: String)] = []
        var steps: [String] = []

        var isComplete: Bool {
            guard let kcal, let protein, let carbs, let fat else { return false }
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !slots.isEmpty
                && (1...20).contains(servings) && (0...600).contains(cookMinutes)
                && (0...5000).contains(kcal) && (0...500).contains(protein) && (0...1000).contains(carbs) && (0...500).contains(fat)
        }
    }

    @discardableResult
    func create(_ own: OwnRecipe) -> Recipe? {
        guard own.isComplete, let kcal = own.kcal, let protein = own.protein, let carbs = own.carbs, let fat = own.fat else { return nil }
        let recipe = Recipe(
            id: UUID(), ownerID: userID, title: LocalizedText([language: own.title.trimmingCharacters(in: .whitespacesAndNewlines)]),
            servings: own.servings, cookMinutes: own.cookMinutes, kcalPerServing: kcal, proteinGPerServing: protein,
            carbsGPerServing: carbs, fatGPerServing: fat, mealSlots: MealSlot.allCases.filter(own.slots.contains), updatedAt: now()
        )
        let steps = own.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !steps.isEmpty { recipe.steps = [language: steps] }
        context.insert(recipe)
        for (position, line) in own.ingredients.enumerated() where line.quantity > 0 && !line.name.isEmpty {
            context.insert(RecipeIngredient(
                id: UUID(), recipeID: recipe.id, ownerID: userID, name: LocalizedText([language: line.name]),
                quantity: line.quantity, unit: line.unit, aisle: "other", position: position, updatedAt: now()
            ))
        }
        try? context.save()
        return recipe
    }

    func delete(_ recipe: Recipe) {
        guard recipe.ownerID == userID else { return }
        recipe.deletedAt = now()
        recipe.updatedAt = now()
        recipe.needsPush = true
        try? context.save()
    }

    // MARK: Preferences

    /// The user's preferences, made with the defaults the first time.
    func preferences() -> MenuPreferences {
        let userID = userID
        var descriptor = FetchDescriptor<MenuPreferences>(predicate: #Predicate<MenuPreferences> { $0.userID == userID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let made = MenuPreferences(userID: userID, updatedAt: now())
        context.insert(made)
        try? context.save()
        return made
    }

    func save(_ preferences: MenuPreferences) {
        preferences.updatedAt = now()
        preferences.needsPush = true
        try? context.save()
    }

    // MARK: Week menu

    /// The week menu from today, by day and in the order of the meals.
    func entries() -> [MealPlanEntry] {
        let userID = userID
        let first = today.isoString
        let last = today.adding(Self.menuDays - 1).isoString
        let slotOrder = Dictionary(uniqueKeysWithValues: MealSlot.allCases.enumerated().map { ($1.rawValue, $0) })
        return ((try? context.fetch(FetchDescriptor<MealPlanEntry>(
            predicate: #Predicate<MealPlanEntry> {
                $0.userID == userID && $0.deletedAt == nil && $0.plannedOn >= first && $0.plannedOn <= last
            }
        ))) ?? []).sorted { ($0.plannedOn, slotOrder[$0.meal] ?? 9) < ($1.plannedOn, slotOrder[$1.meal] ?? 9) }
    }

    /// The targets a menu plans for: the day's own target, or what the formulas give for `goal`.
    func targets(for goal: Goal?) -> NutritionTargets {
        guard let goal, var body = profile.bodyProfile else { return context.targets(on: today, for: profile) }
        body.goal = goal
        return NutritionEngine.plan(for: body, on: today).targets
    }

    /// A new menu from today for `options.days` days. Pinned and already logged meals stay; the rest
    /// is replaced. A different `seed` gives a different menu from the same recipes.
    @discardableResult
    func generate(seed: UInt64, options: MenuOptions = MenuOptions()) -> [MenuIssue] {
        let count = min(max(options.days, 1), Self.menuDays)
        return plan(days: (0..<count).map { today.adding($0) }, replacing: entries(), seed: seed, goal: options.goal)
    }

    /// New meals for one day; the other days stay as they are.
    @discardableResult
    func renew(_ day: Day, seed: UInt64, goal: Goal?) -> [MenuIssue] {
        plan(days: [day], replacing: entries().filter { $0.plannedOn == day.isoString }, seed: seed, goal: goal)
    }

    private func plan(days: [Day], replacing existing: [MealPlanEntry], seed: UInt64, goal: Goal?) -> [MenuIssue] {
        let preferences = preferences()
        let kept = existing.filter { $0.isPinned || $0.loggedEntryID != nil }
        let targets = targets(for: goal)
        let request = MenuRequest(
            days: days, kcalTarget: targets.kcal, proteinTargetG: targets.proteinG,
            slots: preferences.mealSlots.compactMap(MealSlot.init(rawValue:)),
            excludedIngredientIDs: excludedProductIDs(), excludedTags: Set(preferences.excludedTags),
            maxCookMinutes: preferences.maxCookMinutes, budgetCents: preferences.budgetCents, mealPrep: preferences.mealPrep,
            pinned: kept.compactMap(\.plannedMeal).map { meal in
                var meal = meal
                meal.isPinned = true
                return meal
            },
            seed: seed
        )
        let plan = WeekMenuPlanner.plan(request, recipes: plannerRecipes())
        for entry in existing where !kept.contains(where: { $0.id == entry.id }) {
            entry.deletedAt = now()
            entry.updatedAt = now()
            entry.needsPush = true
        }
        let keptSlots = Set(kept.map { "\($0.plannedOn)|\($0.meal)" })
        for meal in plan.meals where !keptSlots.contains("\(meal.day.isoString)|\(meal.slot.rawValue)") {
            var meal = meal
            meal.isPinned = false
            context.insert(MealPlanEntry(id: UUID(), userID: userID, meal: meal, updatedAt: now()))
        }
        try? context.save()
        return plan.issues
    }

    func togglePin(_ entry: MealPlanEntry) {
        entry.isPinned.toggle()
        touch(entry)
    }

    /// Another recipe for this meal; a meal the user chose is pinned, so a new menu keeps it.
    func swap(_ entry: MealPlanEntry, to recipe: Recipe) {
        guard entry.loggedEntryID == nil else { return }
        entry.recipeID = recipe.id
        entry.isLeftover = false
        entry.isPinned = true
        touch(entry)
    }

    func remove(_ entry: MealPlanEntry) {
        entry.deletedAt = now()
        touch(entry)
    }

    /// Logs a planned meal with one tap: one food entry with the recipe's values for the planned
    /// servings. A second tap does nothing.
    @discardableResult
    func log(_ entry: MealPlanEntry) -> FoodEntry? {
        guard entry.loggedEntryID == nil, let recipe = recipe(entry.recipeID), let meal = entry.plannedMeal else { return nil }
        let food = FoodEntry(
            id: UUID(), userID: userID, consumedOn: meal.day, meal: meal.slot,
            name: recipe.title.text(preferring: Locale.preferredLanguages), quantity: entry.servings, quantityUnit: "serving",
            kcal: (recipe.kcalPerServing * entry.servings * 10).rounded() / 10, updatedAt: now()
        )
        food.recipeID = recipe.id
        food.proteinG = (recipe.proteinGPerServing * entry.servings * 10).rounded() / 10
        food.carbsG = (recipe.carbsGPerServing * entry.servings * 10).rounded() / 10
        food.fatG = (recipe.fatGPerServing * entry.servings * 10).rounded() / 10
        context.insert(food)
        entry.loggedEntryID = food.id
        touch(entry)
        return food
    }

    // MARK: Helpers

    private func plannerRecipes() -> [PlannerRecipe] {
        recipes().compactMap { recipe in
            recipe.plannerRecipe(ingredientIDs: Set(ingredients(of: recipe).compactMap(\.productID)))
        }
    }

    private func excludedProductIDs() -> Set<UUID> {
        let userID = userID
        return Set(((try? context.fetch(FetchDescriptor<ExcludedIngredient>(
            predicate: #Predicate<ExcludedIngredient> { $0.userID == userID && $0.deletedAt == nil }
        ))) ?? []).map(\.productID))
    }

    private func touch(_ entry: MealPlanEntry) {
        entry.updatedAt = now()
        entry.needsPush = true
        try? context.save()
    }
}

/// What the user chose for a menu: how many days from today, and a goal other than the daily target.
struct MenuOptions: Equatable, Codable {
    var days = MenuStore.menuDays
    var goal: Goal?
}
