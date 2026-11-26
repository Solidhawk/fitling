import Foundation
import SwiftData
import FitlingCore

/// Recipes, menu preferences and the week menu of one user (TASKS 5.2–5.5).
@MainActor
struct MenuStore {
    /// Read off the main actor too, as the default of `MenuOptions.days`.
    nonisolated static let menuDays = 7

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

    /// Shared and own recipes, by title in the user's language (MenuBook.recipes).
    func recipes() -> [Recipe] {
        let all = recipeModels()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return menuBook(recipes: all.map { $0.menuRecipe(productIDs: []) }).recipes().compactMap { byID[$0.id] }
    }

    /// Recipes that fit this meal, for swapping (MenuBook.recipes(for:)).
    func recipes(for entry: MealPlanEntry) -> [Recipe] {
        let all = recipeModels()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return menuBook(recipes: all.map { $0.menuRecipe(productIDs: []) }, entries: [entry].compactMap(\.menuEntry)).recipes(for: entry.id).compactMap { byID[$0.id] }
    }

    private func recipeModels() -> [Recipe] {
        let owner: UUID? = userID
        return (try? context.fetch(FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { $0.deletedAt == nil && ($0.ownerID == nil || $0.ownerID == owner) }
        ))) ?? []
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

        /// The same rule as on the web (MenuBook.ownRecipeIsComplete).
        var isComplete: Bool {
            MenuBook.ownRecipeIsComplete(
                title: title, servings: servings, cookMinutes: cookMinutes, kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                mealSlots: MealSlot.allCases.filter(slots.contains).map(\.rawValue)
            )
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

    /// The week menu from today, by day and in the order of the meals (MenuBook.entries).
    func entries() -> [MealPlanEntry] {
        let all = entryModels()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return menuBook(entries: all.compactMap(\.menuEntry)).entries().compactMap { byID[$0.id] }
    }

    /// From today on: MenuBook only looks at today and the days after it, and earlier weeks keep growing.
    private func entryModels() -> [MealPlanEntry] {
        let userID = userID
        let first = today.isoString
        return (try? context.fetch(FetchDescriptor<MealPlanEntry>(
            predicate: #Predicate<MealPlanEntry> { $0.userID == userID && $0.deletedAt == nil && $0.plannedOn >= first }
        ))) ?? []
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
        apply(book().generate(days: options.days, seed: seed, targets: targets(for: options.goal)))
    }

    /// New meals for one day; the other days stay as they are.
    @discardableResult
    func renew(_ day: Day, seed: UInt64, goal: Goal?) -> [MenuIssue] {
        apply(book().renew(day, seed: seed, targets: targets(for: goal)))
    }

    /// What FitlingCore decided: the meals that go are removed, those that come are stored.
    private func apply(_ change: MenuChange) -> [MenuIssue] {
        let removed = Set(change.removed)
        for entry in entryModels() where removed.contains(entry.id) {
            entry.deletedAt = now()
            entry.updatedAt = now()
            entry.needsPush = true
        }
        for meal in change.added {
            context.insert(MealPlanEntry(id: UUID(), userID: userID, meal: meal, updatedAt: now()))
        }
        try? context.save()
        return change.issues
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
        guard let meal = book().loggedMeal(entry.id) else { return nil }
        let food = FoodEntry(
            id: UUID(), userID: userID, consumedOn: meal.day, meal: meal.slot, name: meal.name, quantity: meal.servings,
            quantityUnit: "serving", kcal: meal.kcal, updatedAt: now()
        )
        food.recipeID = meal.recipeID
        food.proteinG = meal.proteinG
        food.carbsG = meal.carbsG
        food.fatG = meal.fatG
        context.insert(food)
        entry.loggedEntryID = food.id
        touch(entry)
        return food
    }

    // MARK: MenuBook

    /// Everything on this device that FitlingCore reads for the menu: recipes with their products, the week menu, the
    /// preferences and what the user leaves out.
    func book() -> MenuBook {
        let ingredients = (try? context.fetch(FetchDescriptor<RecipeIngredient>(predicate: #Predicate<RecipeIngredient> { $0.deletedAt == nil }))) ?? []
        let products = Dictionary(grouping: ingredients.filter { $0.productID != nil }, by: \.recipeID).mapValues { $0.compactMap(\.productID) }
        let alive = recipeModels()
        let entries = entryModels().compactMap(\.menuEntry)
        // Removed after they were planned (on another device): their meals keep name and values (MenuBook.recipe).
        let removed = Set(entries.map(\.recipeID)).subtracting(alive.map(\.id)).compactMap { recipe($0) }
        return menuBook(
            recipes: alive.map { $0.menuRecipe(productIDs: products[$0.id] ?? []) },
            removed: removed.map { $0.menuRecipe(productIDs: []) },
            entries: entries,
            settings: preferences().menuSettings,
            excluded: excludedProductIDs()
        )
    }

    private func menuBook(
        recipes: [MenuRecipe] = [], removed: [MenuRecipe] = [], entries: [MenuEntry] = [], settings: MenuSettings = MenuSettings(),
        excluded: Set<UUID> = []
    ) -> MenuBook {
        MenuBook(
            userID: userID, recipes: recipes, removedRecipes: removed, entries: entries, settings: settings, excludedProductIDs: excluded,
            today: today, languages: [language] + Locale.preferredLanguages
        )
    }

    // MARK: Helpers

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

// The SwiftData rows as FitlingCore reads them.

extension Recipe {
    func menuRecipe(productIDs: [UUID]) -> MenuRecipe {
        MenuRecipe(
            id: id, ownerID: ownerID, title: title, servings: servings, cookMinutes: cookMinutes, kcalPerServing: kcalPerServing,
            proteinGPerServing: proteinGPerServing, carbsGPerServing: carbsGPerServing, fatGPerServing: fatGPerServing,
            costCentsPerServing: costCentsPerServing, keepsWell: keepsWell, mealSlots: mealSlots, tags: tags, productIDs: productIDs
        )
    }
}

extension MealPlanEntry {
    /// Nil for an entry whose day cannot be read; it never counts.
    var menuEntry: MenuEntry? {
        Day(isoString: plannedOn).map {
            MenuEntry(
                id: id, plannedOn: $0, meal: meal, recipeID: recipeID, servings: servings, isLeftover: isLeftover, isPinned: isPinned,
                loggedEntryID: loggedEntryID
            )
        }
    }
}

extension MenuPreferences {
    var menuSettings: MenuSettings {
        MenuSettings(excludedTags: excludedTags, maxCookMinutes: maxCookMinutes, budgetCents: budgetCents, mealPrep: mealPrep, mealSlots: mealSlots)
    }
}
