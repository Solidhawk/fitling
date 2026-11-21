import Foundation
import SwiftData
import Testing
import UIKit
import FitlingCore
@testable import Fitling

@MainActor
struct MenuFixture {
    let container: ModelContainer
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let defaults: UserDefaults
    let profile: UserProfile
    var context: ModelContext { container.mainContext }
    var today: Day { Day(now, timeZone: .gmt) }

    init() throws {
        container = try makeModelContainer(inMemory: true)
        let suite = "MenuTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        profile = UserProfile(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body,
            targets: NutritionTargets(kcal: 2500, proteinG: 130, carbsG: 300, fatG: 80), targetsAreManual: false, updatedAt: now
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        try #require(RecipeCatalog.bundled()).install(into: container.mainContext, defaults: defaults, now: now)
    }

    var store: MenuStore {
        MenuStore(context: context, profile: profile, timeZone: .gmt, now: { [now] in now }, language: "nl")
    }
}

// MARK: - 5.1 Recepten

@MainActor
@Suite struct RecipeCatalogTests {
    let fixture: MenuFixture
    init() throws { fixture = try MenuFixture() }

    @Test func catalogInstallsTheSharedRecipes() throws {
        let catalog = try #require(RecipeCatalog.bundled())
        let recipes = fixture.store.recipes()
        #expect(recipes.count == catalog.recipes.count)
        #expect(recipes.allSatisfy { $0.ownerID == nil && !$0.needsPush && $0.kcalPerServing > 0 })
        #expect(try fixture.context.fetchCount(RecipeIngredient.pending) == 0)
    }

    @Test func everySharedRecipeHasItsPhotoAndCredit() throws {
        let catalog = try #require(RecipeCatalog.bundled())
        for recipe in catalog.recipes {
            #expect(UIImage(named: RecipeThumbnail.photoName(recipe.id)) != nil, "\(recipe.title.values["en"] ?? "")")
            #expect(!recipe.photoCredit.author.isEmpty && !recipe.photoCredit.licence.isEmpty)
        }
    }

    @Test func ownRecipesNeedTheirValues() {
        var own = MenuStore.OwnRecipe(title: "Pasta pesto", servings: 2, cookMinutes: 20, kcal: 550, protein: 18, carbs: 70, fat: nil, slots: [.dinner])
        #expect(fixture.store.create(own) == nil)
        own.fat = 20
        own.ingredients = [("Pasta", 200, "g"), ("Pesto", 0, "g")]
        let recipe = fixture.store.create(own)
        #expect(recipe?.ownerID == fixture.userID)
        #expect(recipe?.needsPush == true)
        #expect(recipe.map { fixture.store.ingredients(of: $0).map(\.quantity) } == [200])
    }
}

// MARK: - 5.4 en 5.5 Weekmenu en loggen

@MainActor
@Suite struct WeekMenuTests {
    let fixture: MenuFixture
    init() throws { fixture = try MenuFixture() }

    @Test func generatingStoresOneEntryPerPlannedMeal() {
        let issues = fixture.store.generate(seed: 1)
        let entries = fixture.store.entries()
        let slots = fixture.store.preferences().mealSlots.count
        #expect(entries.count == MenuStore.menuDays * slots)
        let keys = entries.map { "\($0.plannedOn)|\($0.meal)" }
        #expect(Set(keys).count == keys.count)
        #expect(entries.allSatisfy { $0.needsPush && !$0.isPinned })
        #expect(issues.allSatisfy { if case .noRecipes = $0 { false } else { true } })
    }

    @Test func pinnedMealsSurviveANewMenu() throws {
        fixture.store.generate(seed: 1)
        let pinned = try #require(fixture.store.entries().first)
        fixture.store.togglePin(pinned)
        let recipe = pinned.recipeID

        fixture.store.generate(seed: 2)
        let after = fixture.store.entries()
        #expect(after.contains { $0.id == pinned.id && $0.recipeID == recipe && $0.isPinned })
        #expect(after.filter { $0.plannedOn == pinned.plannedOn && $0.meal == pinned.meal }.count == 1)
    }

    @Test func issuesAreShown() {
        let preferences = fixture.store.preferences()
        preferences.excludedTags = ["meat", "fish", "dairy", "egg", "gluten", "nuts", "soy", "sesame"]
        preferences.mealSlots = ["breakfast", "lunch", "dinner"]
        fixture.store.save(preferences)
        let issues = fixture.store.generate(seed: 1)
        #expect(issues.contains(.noRecipes(slot: .breakfast)))
    }

    @Test func excludedTagsAreRespected() {
        let preferences = fixture.store.preferences()
        preferences.excludedTags = ["meat", "fish"]
        fixture.store.save(preferences)
        fixture.store.generate(seed: 3)
        let recipes = fixture.store.entries().compactMap { fixture.store.recipe($0.recipeID) }
        #expect(!recipes.isEmpty)
        #expect(recipes.allSatisfy { $0.tags.allSatisfy { !["meat", "fish"].contains($0) } })
    }

    @Test func swappingPinsTheMeal() throws {
        fixture.store.generate(seed: 1)
        let entry = try #require(fixture.store.entries().first)
        let other = try #require(fixture.store.recipes().first { $0.id != entry.recipeID && $0.mealSlots.contains(entry.meal) })
        fixture.store.swap(entry, to: other)
        #expect(entry.recipeID == other.id)
        #expect(entry.isPinned)
    }

    @Test func loggingOnceWithOneTap() throws {
        fixture.store.generate(seed: 1)
        let entry = try #require(fixture.store.entries().first)
        let recipe = try #require(fixture.store.recipe(entry.recipeID))

        let food = try #require(fixture.store.log(entry))
        #expect(food.recipeID == recipe.id)
        #expect(food.consumedOn == entry.plannedOn)
        #expect(food.meal == entry.meal)
        #expect(abs(food.kcal - recipe.kcalPerServing * entry.servings) < 0.1)
        #expect(entry.loggedEntryID == food.id)

        #expect(fixture.store.log(entry) == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FoodEntry>()) == 1)
    }

    // MARK: Menu generator (feedback 2026-11-21: days, goal, what not to eat, adjust per day)

    @Test func aMenuCanCoverFewerDays() {
        fixture.store.generate(seed: 1, options: MenuOptions(days: 5))
        let days = Set(fixture.store.entries().map(\.plannedOn))
        #expect(days == Set((0..<5).map { fixture.today.adding($0).isoString }))
    }

    @Test func aMenuForAnotherGoalUsesThatGoalsTarget() throws {
        var losing = try #require(fixture.profile.bodyProfile)
        losing.goal = .lose
        #expect(fixture.store.targets(for: .lose) == NutritionEngine.plan(for: losing, on: fixture.today).targets)
        #expect(fixture.store.targets(for: nil) == fixture.context.targets(on: fixture.today, for: fixture.profile))
        #expect(fixture.store.targets(for: .lose).kcal < fixture.store.targets(for: .buildMuscle).kcal)
    }

    @Test func renewingOneDayKeepsTheOtherDays() {
        fixture.store.generate(seed: 1)
        let before = fixture.store.entries()
        let day = fixture.today.isoString
        let others = Set(before.filter { $0.plannedOn != day }.map(\.id))

        fixture.store.renew(fixture.today, seed: 99, goal: nil)
        let after = fixture.store.entries()
        #expect(Set(after.filter { $0.plannedOn != day }.map(\.id)) == others)
        let renewed = after.filter { $0.plannedOn == day }
        #expect(renewed.count == fixture.store.preferences().mealSlots.count)
        #expect(renewed.allSatisfy { entry in !before.contains { $0.id == entry.id } })
    }

    @Test func theLastMenuChoicesAreRemembered() {
        let first = MenuViewModel(profile: fixture.profile, context: fixture.context, defaults: fixture.defaults, timeZone: .gmt, now: { [now = fixture.now] in now }, seed: { 1 })
        #expect(first.options == MenuOptions())
        first.generate(MenuOptions(days: 4, goal: .lose))
        let again = MenuViewModel(profile: fixture.profile, context: fixture.context, defaults: fixture.defaults, timeZone: .gmt, now: { [now = fixture.now] in now }, seed: { 1 })
        #expect(again.options == MenuOptions(days: 4, goal: .lose))
        #expect(Set(again.entries.map(\.plannedOn)).count == 4)
    }

    @Test func loggedMealsStayInANewMenu() throws {
        fixture.store.generate(seed: 1)
        let entry = try #require(fixture.store.entries().first)
        fixture.store.log(entry)
        fixture.store.generate(seed: 9)
        #expect(fixture.store.entries().contains { $0.id == entry.id && $0.loggedEntryID != nil })
    }

    @Test func menuRecordsKeepEveryColumn() throws {
        fixture.store.generate(seed: 1)
        let entry = try #require(fixture.store.entries().first)
        let decoded = try JSONDecoder().decode(MealPlanEntryRecord.self, from: JSONEncoder().encode(entry.record))
        #expect(decoded == entry.record)
        let recipe = try #require(fixture.store.recipe(entry.recipeID))
        let decodedRecipe = try JSONDecoder().decode(RecipeRecord.self, from: JSONEncoder().encode(recipe.record))
        #expect(decodedRecipe == recipe.record)
    }
}
