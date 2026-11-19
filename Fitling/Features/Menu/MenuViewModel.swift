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

    /// A new menu; pinned and logged meals stay.
    func generate() {
        issues = store.generate(seed: randomSeed())
        entries = store.entries()
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
        recipes.filter { $0.mealSlots.contains(entry.meal) && $0.id != entry.recipeID }
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
