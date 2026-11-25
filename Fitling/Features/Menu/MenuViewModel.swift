import Foundation
import Observation
import SwiftData
import FitlingCore

/// The menu tab: the week menu, what the planner could not solve, and the recipes.
@Observable
@MainActor
final class MenuViewModel {
    private(set) var entries: [MealPlanEntry] = []
    private(set) var issues: [MenuIssue] = []
    private(set) var recipes: [Recipe] = []

    let store: MenuStore
    private let defaults: UserDefaults
    private var randomSeed: () -> UInt64

    init(
        profile: UserProfile, context: ModelContext, defaults: UserDefaults = .standard, timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init, seed: @escaping () -> UInt64 = { UInt64.random(in: 0...UInt64.max) }
    ) {
        store = MenuStore(context: context, profile: profile, timeZone: timeZone, now: now)
        self.defaults = defaults
        randomSeed = seed
    }

    /// The meals of the menu, per day in order.
    var days: [(day: Day, entries: [MealPlanEntry])] {
        let grouped = Dictionary(grouping: entries) { $0.plannedOn }
        return store.menuDays.compactMap { day in grouped[day.isoString].map { (day, $0) } }
    }

    func reload() {
        RecipeCatalog.bundled()?.install(into: store.context, defaults: defaults)
        entries = store.entries()
        recipes = store.recipes()
    }

    private static let optionsKey = "fitling.menuOptions"

    /// What the user chose for the last menu: the generator opens with it, and renewing a day uses its goal.
    var options: MenuOptions {
        guard let data = defaults.data(forKey: Self.optionsKey),
              let options = try? JSONDecoder().decode(MenuOptions.self, from: data) else { return MenuOptions() }
        return options
    }

    /// A new menu with these choices; pinned and logged meals stay.
    func generate(_ options: MenuOptions) {
        if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: Self.optionsKey) }
        issues = store.generate(seed: randomSeed(), options: options)
        entries = store.entries()
    }

    /// New meals for one day, for the goal of the last menu.
    func renew(_ day: Day) {
        issues = store.renew(day, seed: randomSeed(), goal: options.goal)
        entries = store.entries()
    }

    /// The kcal and protein a menu for `goal` plans for, to show beside each choice.
    func targets(for goal: Goal?) -> NutritionTargets {
        store.targets(for: goal)
    }

    func recipe(of entry: MealPlanEntry) -> Recipe? {
        store.recipe(entry.recipeID)
    }

    func togglePin(_ entry: MealPlanEntry) {
        store.togglePin(entry)
        entries = store.entries()
    }

    func swap(_ entry: MealPlanEntry, to recipe: Recipe) {
        store.swap(entry, to: recipe)
        entries = store.entries()
    }

    func remove(_ entry: MealPlanEntry) {
        store.remove(entry)
        entries = store.entries()
    }

    func log(_ entry: MealPlanEntry) {
        store.log(entry)
        entries = store.entries()
    }

    /// Recipes that fit this meal, for swapping.
    func recipes(for entry: MealPlanEntry) -> [Recipe] {
        store.recipes(for: entry)
    }

    func create(_ own: MenuStore.OwnRecipe) -> Recipe? {
        let recipe = store.create(own)
        recipes = store.recipes()
        return recipe
    }

    func delete(_ recipe: Recipe) {
        store.delete(recipe)
        recipes = store.recipes()
    }
}
