#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The menu tab for the web (phase 5): what MenuStore and MenuViewModel read and decide on iOS, from the same
// MenuBook. Ids go out in lower case, as Postgres writes them.

/// The user's recipes, week menu and preferences, and the shared recipes, as the web read them from Supabase.
struct MenuInput: Decodable {
    let userID: UUID
    let today: String
    let languages: [String]
    let recipes: [MenuRecipe]
    /// Removed after they were planned: their meals keep name and values (MenuBook.recipe).
    let removedRecipes: [MenuRecipe]
    let entries: [MenuEntry]
    let settings: MenuSettings
    let excludedProductIDs: [UUID]

    func book() throws -> MenuBook {
        MenuBook(
            userID: userID, recipes: recipes, removedRecipes: removedRecipes, entries: entries, settings: settings,
            excludedProductIDs: Set(excludedProductIDs), today: try day(today, "today"), languages: languages
        )
    }
}

struct MenuBookRequest: Decodable {
    let menu: MenuInput
}

struct RecipeSummary: Encodable {
    let id: String
    let title: String
    let kcalPerServing: Double
    let cookMinutes: Int
    let own: Bool
    let mealSlots: [String]

    init(_ recipe: MenuRecipe, in book: MenuBook) {
        id = lower(recipe.id)
        title = recipe.title.text(preferring: book.languages)
        kcalPerServing = recipe.kcalPerServing
        cookMinutes = recipe.cookMinutes
        own = recipe.ownerID == book.userID
        mealSlots = recipe.mealSlots
    }
}

struct MenuEntryOutput: Encodable {
    let id: String
    let slot: String
    let recipeID: String
    /// Empty when the recipe is gone (removed on another device): the meal still shows, without a name.
    let title: String
    let servings: Double
    /// The recipe's energy for the planned servings, rounded.
    let kcal: Int
    let isPinned: Bool
    let logged: Bool
}

struct MenuDayOutput: Encodable {
    let day: String
    let entries: [MenuEntryOutput]
}

struct MenuOverviewAnswer: Encodable {
    let days: [MenuDayOutput]
    let recipes: [RecipeSummary]
}

/// The menu tab (MenuViewModel.days and recipes): per day from today the planned meals in their order.
func menuOverview(_ request: MenuBookRequest) throws -> MenuOverviewAnswer {
    let book = try request.menu.book()
    let entries = book.entries()
    let days = book.menuDays.compactMap { day -> MenuDayOutput? in
        let ofDay = entries.filter { $0.plannedOn == day }
        guard !ofDay.isEmpty else { return nil }
        return MenuDayOutput(day: day.isoString, entries: ofDay.map { entry in
            let recipe = book.recipe(entry.recipeID)
            return MenuEntryOutput(
                id: lower(entry.id), slot: entry.meal, recipeID: lower(entry.recipeID), title: recipe?.title.text(preferring: book.languages) ?? "",
                servings: entry.servings, kcal: Int(((recipe?.kcalPerServing ?? 0) * entry.servings).rounded()), isPinned: entry.isPinned,
                logged: entry.loggedEntryID != nil
            )
        })
    }
    return MenuOverviewAnswer(days: days, recipes: book.recipes().map { RecipeSummary($0, in: book) })
}

struct IssueOutput: Encodable {
    /// noRecipes, kcalOutOfRange, proteinShort or overBudget.
    let kind: String
    var slot: String?
    var day: String?
    var kcal: Int?
    var missingG: Int?
    var byCents: Int?

    init(_ issue: MenuIssue) {
        switch issue {
        case let .noRecipes(slot): (kind, self.slot) = ("noRecipes", slot.rawValue)
        case let .kcalOutOfRange(day, kcal): (kind, self.day, self.kcal) = ("kcalOutOfRange", day.isoString, kcal)
        case let .proteinShort(day, missing): (kind, self.day, missingG) = ("proteinShort", day.isoString, missing)
        case let .overBudget(cents): (kind, byCents) = ("overBudget", cents)
        }
    }
}

struct PlannedMealOutput: Encodable {
    let day: String
    let slot: String
    let recipeID: String
    let servings: Double
    let isLeftover: Bool
}

struct MenuChangeAnswer: Encodable {
    let removed: [String]
    let added: [PlannedMealOutput]
    let issues: [IssueOutput]

    init(_ change: MenuChange) {
        removed = change.removed.map(lower)
        added = change.added.map {
            PlannedMealOutput(day: $0.day.isoString, slot: $0.slot.rawValue, recipeID: lower($0.recipeID), servings: $0.servings, isLeftover: $0.isLeftover)
        }
        issues = change.issues.map(IssueOutput.init)
    }
}

struct GenerateRequest: Decodable {
    let menu: MenuInput
    let days: Int
    /// A UInt64 as text: JavaScript numbers do not hold it.
    let seed: String
    let targets: NutritionTargets
}

/// A new menu from today for `days` days; pinned and logged meals stay (MenuStore.generate).
func menuGenerate(_ request: GenerateRequest) throws -> MenuChangeAnswer {
    MenuChangeAnswer(try request.menu.book().generate(days: request.days, seed: UInt64(request.seed) ?? 0, targets: request.targets))
}

struct RenewRequest: Decodable {
    let menu: MenuInput
    let day: String
    let seed: String
    let targets: NutritionTargets
}

/// New meals for one day; the other days stay (MenuStore.renew).
func menuRenew(_ request: RenewRequest) throws -> MenuChangeAnswer {
    MenuChangeAnswer(try request.menu.book().renew(try day(request.day, "day"), seed: UInt64(request.seed) ?? 0, targets: request.targets))
}

struct EntryRequest: Decodable {
    let menu: MenuInput
    let entryID: UUID
}

struct LoggedMealOutput: Encodable {
    let recipeID: String
    let name: String
    let day: String
    let slot: String
    let servings: Double
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct LoggedMealAnswer: Encodable {
    /// Nil for a meal already logged or whose recipe is gone: a second tap does nothing.
    let meal: LoggedMealOutput?
}

/// The food entry a meal logged with one tap becomes (MenuStore.log).
func menuLoggedMeal(_ request: EntryRequest) throws -> LoggedMealAnswer {
    let meal = try request.menu.book().loggedMeal(request.entryID)
    return LoggedMealAnswer(meal: meal.map {
        LoggedMealOutput(
            recipeID: lower($0.recipeID), name: $0.name, day: $0.day.isoString, slot: $0.slot.rawValue, servings: $0.servings, kcal: $0.kcal,
            proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG
        )
    })
}

/// Recipes to swap a meal for: the same meal, another recipe (MenuViewModel.recipes(for:)).
func menuRecipesFor(_ request: EntryRequest) throws -> [RecipeSummary] {
    let book = try request.menu.book()
    return book.recipes(for: request.entryID).map { RecipeSummary($0, in: book) }
}

struct OwnRecipeRequest: Decodable {
    let title: String
    let servings: Int
    let cookMinutes: Int
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let mealSlots: [String]
}

struct OwnRecipeAnswer: Encodable {
    let complete: Bool
}

/// Whether a recipe of the user's own can be kept (MenuStore.OwnRecipe.isComplete).
func ownRecipeComplete(_ request: OwnRecipeRequest) -> OwnRecipeAnswer {
    OwnRecipeAnswer(complete: MenuBook.ownRecipeIsComplete(
        title: request.title, servings: request.servings, cookMinutes: request.cookMinutes, kcal: request.kcal, protein: request.protein,
        carbs: request.carbs, fat: request.fat, mealSlots: request.mealSlots
    ))
}
