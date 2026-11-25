import Foundation
import Testing
@testable import FitlingCore

/// The week menu as the app and the web share it (web phase 5); MenuTests in the app check the same through MenuStore.
@Suite struct MenuBookTests {
    let user = UUID()
    let today = Day(isoString: "2026-11-18")!
    let targets = NutritionTargets(kcal: 2200, proteinG: 120, carbsG: 250, fatG: 70)

    /// Three recipes per meal, so the planner can fill every day.
    var recipes: [MenuRecipe] {
        ["breakfast", "lunch", "dinner"].flatMap { slot in
            (1...3).map { number in
                MenuRecipe(
                    id: UUID(), ownerID: nil, title: LocalizedText(["nl": "\(slot) \(number)"]), servings: 2, cookMinutes: 20,
                    kcalPerServing: slot == "dinner" ? 800 : 600, proteinGPerServing: 35, carbsGPerServing: 70, fatGPerServing: 20, mealSlots: [slot]
                )
            }
        }
    }

    func book(_ recipes: [MenuRecipe], _ entries: [MenuEntry], settings: MenuSettings = MenuSettings()) -> MenuBook {
        MenuBook(userID: user, recipes: recipes, entries: entries, settings: settings, excludedProductIDs: [], today: today, languages: ["nl"])
    }

    func entry(_ days: Int, _ meal: String, _ recipe: MenuRecipe, pinned: Bool = false, logged: Bool = false) -> MenuEntry {
        MenuEntry(id: UUID(), plannedOn: today.adding(days), meal: meal, recipeID: recipe.id, servings: 1, isPinned: pinned, loggedEntryID: logged ? UUID() : nil)
    }

    @Test func pinnedAndLoggedMealsStay() {
        let all = recipes
        let pinned = entry(0, "dinner", all[6], pinned: true)
        let logged = entry(1, "lunch", all[3], logged: true)
        let plain = entry(0, "breakfast", all[0])
        let change = book(all, [pinned, logged, plain]).generate(days: 7, seed: 1, targets: targets)
        #expect(change.removed == [plain.id])
        #expect(!change.added.contains { $0.day == pinned.plannedOn && $0.slot == .dinner })
        #expect(!change.added.contains { $0.day == logged.plannedOn && $0.slot == .lunch })
        // One meal per slot per day, less the two that stayed.
        #expect(change.added.count == 7 * 3 - 2)
        #expect(change.added.allSatisfy { !$0.isPinned })
    }

    @Test func renewingADayLeavesTheOthers() {
        let all = recipes
        let todays = [entry(0, "breakfast", all[0]), entry(0, "dinner", all[6])]
        let tomorrows = entry(1, "lunch", all[3])
        let change = book(all, todays + [tomorrows]).renew(today, seed: 9, targets: targets)
        #expect(Set(change.removed) == Set(todays.map(\.id)))
        #expect(change.added.allSatisfy { $0.day == today })
        #expect(change.added.count == 3)
    }

    @Test func aMenuCoversTheChosenDaysOnly() {
        let change = book(recipes, []).generate(days: 5, seed: 1, targets: targets)
        #expect(Set(change.added.map(\.day)) == Set((0..<5).map { today.adding($0) }))
        // Never more than a week, never less than a day.
        #expect(Set(book(recipes, []).generate(days: 12, seed: 1, targets: targets).added.map(\.day)).count == 7)
        #expect(Set(book(recipes, []).generate(days: 0, seed: 1, targets: targets).added.map(\.day)) == [today])
    }

    @Test func entriesComeByDayAndMeal() {
        let all = recipes
        let shown = [entry(1, "breakfast", all[0]), entry(0, "dinner", all[6]), entry(0, "breakfast", all[1])]
        let hidden = [entry(-1, "lunch", all[3]), entry(7, "lunch", all[4])]
        let entries = book(all, hidden + shown).entries()
        #expect(entries.map(\.id) == [shown[2].id, shown[1].id, shown[0].id])
    }

    @Test func aLoggedMealHasTheRecipesValuesForItsServings() throws {
        let recipe = MenuRecipe(
            id: UUID(), ownerID: nil, title: LocalizedText(["nl": "Pasta pesto", "en": "Pesto pasta"]), servings: 2, cookMinutes: 20,
            kcalPerServing: 512.34, proteinGPerServing: 20.04, carbsGPerServing: 70, fatGPerServing: 18.33, mealSlots: ["dinner"]
        )
        var planned = entry(0, "dinner", recipe)
        planned.servings = 1.5
        let meal = try #require(book([recipe], [planned]).loggedMeal(planned.id))
        #expect(meal.name == "Pasta pesto" && meal.slot == .dinner && meal.day == today && meal.servings == 1.5)
        #expect(meal.kcal == 768.5 && meal.proteinG == 30.1 && meal.carbsG == 105 && meal.fatG == 27.5)
        planned.loggedEntryID = UUID()
        #expect(book([recipe], [planned]).loggedMeal(planned.id) == nil)
    }

    @Test func recipesForAMealAreThoseOfItsMeal() {
        let all = recipes
        let planned = entry(0, "dinner", all[6])
        let fitting = book(all, [planned]).recipes(for: planned.id)
        #expect(Set(fitting.map(\.id)) == Set([all[7].id, all[8].id]))
    }

    @Test func anOwnRecipeNeedsTitleMealsAndMacros() {
        #expect(MenuBook.ownRecipeIsComplete(title: "Pasta pesto", servings: 2, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: 20, mealSlots: ["dinner"]))
        #expect(!MenuBook.ownRecipeIsComplete(title: "Pasta pesto", servings: 2, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: nil, mealSlots: ["dinner"]))
        #expect(!MenuBook.ownRecipeIsComplete(title: "  ", servings: 2, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: 20, mealSlots: ["dinner"]))
        #expect(!MenuBook.ownRecipeIsComplete(title: "Pasta pesto", servings: 2, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: 20, mealSlots: []))
        #expect(!MenuBook.ownRecipeIsComplete(title: "Pasta pesto", servings: 21, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: 20, mealSlots: ["dinner"]))
    }

    @Test func recipesComeByTitle() {
        let titles = ["Zuurdesem toast", "appeltaart", "Éénpansgerecht"]
        let rows = titles.map {
            MenuRecipe(id: UUID(), ownerID: nil, title: LocalizedText(["nl": $0]), servings: 1, cookMinutes: 5, kcalPerServing: 300, proteinGPerServing: 10, carbsGPerServing: 30, fatGPerServing: 10, mealSlots: ["lunch"])
        }
        let other = MenuRecipe(id: UUID(), ownerID: UUID(), title: LocalizedText(["nl": "Van iemand anders"]), servings: 1, cookMinutes: 5, kcalPerServing: 300, proteinGPerServing: 10, carbsGPerServing: 30, fatGPerServing: 10, mealSlots: ["lunch"])
        #expect(book(rows + [other], []).recipes().map { $0.title.text(preferring: ["nl"]) } == ["appeltaart", "Éénpansgerecht", "Zuurdesem toast"])
    }
}
