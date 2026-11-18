import Foundation
import Testing
@testable import FitlingCore

@Suite struct WeekMenuPlannerTests {
    static let fishIngredient = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    static func recipe(
        _ number: Int, _ slot: MealSlot, kcal: Double, protein: Double, minutes: Int, cents: Int,
        tags: Set<String> = [], ingredients: Set<UUID> = []
    ) -> PlannerRecipe {
        PlannerRecipe(
            id: id(number), kcalPerServing: kcal, proteinPerServing: protein, cookMinutes: minutes, costCentsPerServing: cents,
            slots: [slot], tags: tags, ingredientIDs: ingredients, keepsWell: slot == .dinner
        )
    }

    static let breakfasts = [
        recipe(101, .breakfast, kcal: 450, protein: 30, minutes: 5, cents: 100),
        recipe(102, .breakfast, kcal: 500, protein: 33, minutes: 10, cents: 110),
        recipe(103, .breakfast, kcal: 420, protein: 28, minutes: 5, cents: 120),
        recipe(104, .breakfast, kcal: 520, protein: 35, minutes: 10, cents: 130),
        recipe(105, .breakfast, kcal: 480, protein: 32, minutes: 5, cents: 150),
    ]
    static let lunches = [
        recipe(201, .lunch, kcal: 600, protein: 40, minutes: 10, cents: 200),
        recipe(202, .lunch, kcal: 650, protein: 42, minutes: 15, cents: 210, tags: ["fish"]),
        recipe(203, .lunch, kcal: 580, protein: 38, minutes: 10, cents: 220),
        recipe(204, .lunch, kcal: 700, protein: 46, minutes: 25, cents: 240),
        recipe(205, .lunch, kcal: 620, protein: 41, minutes: 20, cents: 280),
        recipe(206, .lunch, kcal: 640, protein: 42, minutes: 15, cents: 300),
    ]
    static let dinners = [
        recipe(301, .dinner, kcal: 750, protein: 50, minutes: 20, cents: 300, ingredients: [fishIngredient]),
        recipe(302, .dinner, kcal: 800, protein: 53, minutes: 25, cents: 320),
        recipe(303, .dinner, kcal: 700, protein: 48, minutes: 30, cents: 340, tags: ["fish"]),
        recipe(304, .dinner, kcal: 850, protein: 56, minutes: 30, cents: 360),
        recipe(305, .dinner, kcal: 720, protein: 47, minutes: 45, cents: 420),
        recipe(306, .dinner, kcal: 780, protein: 51, minutes: 60, cents: 480),
        recipe(307, .dinner, kcal: 760, protein: 50, minutes: 25, cents: 500),
    ]
    static let snacks = [
        recipe(401, .snack, kcal: 200, protein: 15, minutes: 0, cents: 60),
        recipe(402, .snack, kcal: 180, protein: 12, minutes: 0, cents: 50),
        recipe(403, .snack, kcal: 250, protein: 18, minutes: 5, cents: 80),
        recipe(404, .snack, kcal: 220, protein: 14, minutes: 0, cents: 70),
    ]
    static let pool = breakfasts + lunches + dinners
    static let byID = Dictionary(uniqueKeysWithValues: (pool + snacks).map { ($0.id, $0) })

    let week = (0..<7).map { day(2026, 11, 16).adding($0) }

    func request(
        slots: [MealSlot] = [.breakfast, .lunch, .dinner], excludedIngredients: Set<UUID> = [], excludedTags: Set<String> = [],
        maxCookMinutes: Int? = nil, budgetCents: Int? = nil, mealPrep: Bool = false, pinned: [PlannedMeal] = [], seed: UInt64 = 1
    ) -> MenuRequest {
        MenuRequest(
            days: week, kcalTarget: 2200, proteinTargetG: 130, slots: slots,
            excludedIngredientIDs: excludedIngredients, excludedTags: excludedTags, maxCookMinutes: maxCookMinutes,
            budgetCents: budgetCents, mealPrep: mealPrep, pinned: pinned, seed: seed
        )
    }

    func kcal(_ plan: MenuPlan, on day: Day) -> Double {
        plan.meals.filter { $0.day == day }.reduce(0) { $0 + $1.servings * (Self.byID[$1.recipeID]?.kcalPerServing ?? 0) }
    }

    func protein(_ plan: MenuPlan, on day: Day) -> Double {
        plan.meals.filter { $0.day == day }.reduce(0) { $0 + $1.servings * (Self.byID[$1.recipeID]?.proteinPerServing ?? 0) }
    }

    func cost(_ plan: MenuPlan) -> Double {
        plan.meals.reduce(0) { $0 + $1.servings * Double(Self.byID[$1.recipeID]?.costCentsPerServing ?? 0) }
    }

    func dinners(_ plan: MenuPlan) -> [PlannedMeal] {
        plan.meals.filter { $0.slot == .dinner }.sorted { $0.day < $1.day }
    }

    @Test func plansEveryMealOfTheWeek() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        #expect(plan.meals.count == 21)
        #expect(plan.issues.isEmpty)
        for day in week {
            #expect(Set(plan.meals.filter { $0.day == day }.map(\.slot)) == [.breakfast, .lunch, .dinner])
        }
    }

    @Test func everyDayLandsWithinFivePercentOfTheKcalTarget() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        for day in week {
            #expect((2090.0...2310.0).contains(kcal(plan, on: day)))
        }
    }

    @Test func everyDayReachesTheProteinTarget() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        for day in week {
            #expect(protein(plan, on: day) >= 130)
        }
    }

    @Test func servingsStayInQuarterStepsBetweenHalfAndDouble() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        for meal in plan.meals {
            #expect(WeekMenuPlanner.servingRange.contains(meal.servings))
            #expect((meal.servings / WeekMenuPlanner.servingStep).rounded() == meal.servings / WeekMenuPlanner.servingStep)
        }
    }

    @Test func excludedIngredientsAndTagsNeverAppear() {
        let plan = WeekMenuPlanner.plan(request(excludedIngredients: [Self.fishIngredient], excludedTags: ["fish"]), recipes: Self.pool)
        let used = Set(plan.meals.map(\.recipeID))
        #expect(used.isDisjoint(with: [Self.id(202), Self.id(301), Self.id(303)]))
        #expect(plan.meals.count == 21)
    }

    @Test func respectsTheLongestCookingTime() {
        let plan = WeekMenuPlanner.plan(request(maxCookMinutes: 30), recipes: Self.pool)
        #expect(plan.meals.count == 21)
        for meal in plan.meals {
            #expect((Self.byID[meal.recipeID]?.cookMinutes ?? 0) <= 30)
        }
    }

    @Test func usesNoRecipeOnMoreThanTwoDays() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        let uses = Dictionary(grouping: plan.meals, by: \.recipeID).mapValues(\.count)
        #expect(uses.values.allSatisfy { $0 <= WeekMenuPlanner.maxUsesPerRecipe })
    }

    @Test func mealPrepCooksDinnerOnceForTwoDays() {
        let plan = WeekMenuPlanner.plan(request(mealPrep: true), recipes: Self.pool)
        let evening = dinners(plan)
        #expect(evening.count == 7)
        for cooked in stride(from: 0, to: 6, by: 2) {
            #expect(evening[cooked].isLeftover == false)
            #expect(evening[cooked + 1].isLeftover)
            #expect(evening[cooked + 1].recipeID == evening[cooked].recipeID)
        }
        #expect(evening[6].isLeftover == false)
        #expect(Set(evening.map(\.recipeID)).count == 4)
    }

    @Test func withoutMealPrepNoDinnerIsALeftover() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        #expect(plan.meals.allSatisfy { $0.isLeftover == false })
    }

    @Test func keepsPinnedMealsExactlyAsTheyAre() {
        let pinned = PlannedMeal(day: week[2], slot: .dinner, recipeID: Self.id(306), servings: 1.5, isPinned: true)
        let plan = WeekMenuPlanner.plan(request(pinned: [pinned]), recipes: Self.pool)
        #expect(plan.meals.filter { $0.day == week[2] && $0.slot == .dinner } == [pinned])
        #expect(plan.meals.count == 21)
    }

    @Test func staysWithinTheBudgetWhenCheaperRecipesExist() {
        let free = WeekMenuPlanner.plan(request(), recipes: Self.pool)
        let budget = 6000
        let plan = WeekMenuPlanner.plan(request(budgetCents: budget), recipes: Self.pool)
        #expect(cost(plan) <= Double(budget))
        #expect(plan.issues.isEmpty)
        #expect(cost(plan) <= cost(free))
        for day in week {
            #expect((2090.0...2310.0).contains(kcal(plan, on: day)))
        }
    }

    @Test func reportsBeingOverBudgetWhenNoMenuFits() {
        let plan = WeekMenuPlanner.plan(request(budgetCents: 1000), recipes: Self.pool)
        let overBudget = plan.issues.contains { issue in
            if case let .overBudget(byCents) = issue { return byCents > 0 }
            return false
        }
        #expect(overBudget)
        #expect(plan.meals.count == 21)
    }

    @Test func reportsASlotWithoutRecipesOnceAndPlansTheRest() {
        let plan = WeekMenuPlanner.plan(request(), recipes: Self.lunches + Self.dinners)
        #expect(plan.issues.filter { $0 == .noRecipes(slot: .breakfast) }.count == 1)
        #expect(plan.meals.count == 14)
    }

    @Test func reportsDaysThatCannotReachTheKcalTarget() {
        let tiny = [
            Self.recipe(901, .breakfast, kcal: 100, protein: 20, minutes: 5, cents: 100),
            Self.recipe(902, .lunch, kcal: 100, protein: 20, minutes: 5, cents: 100),
            Self.recipe(903, .dinner, kcal: 100, protein: 20, minutes: 5, cents: 100),
        ]
        let plan = WeekMenuPlanner.plan(request(), recipes: tiny)
        #expect(plan.issues.contains(.kcalOutOfRange(day: week[0], kcal: 600)))
    }

    @Test func reportsDaysThatStayShortOfProtein() {
        let lean = (Self.pool).map { recipe in
            var copy = recipe
            copy.proteinPerServing = recipe.kcalPerServing * 0.02
            return copy
        }
        let plan = WeekMenuPlanner.plan(request(), recipes: lean)
        let shortDays = plan.issues.filter { issue in
            if case .proteinShort = issue { return true }
            return false
        }
        #expect(shortDays.count == 7)
    }

    @Test func plansASnackWhenAsked() {
        let plan = WeekMenuPlanner.plan(request(slots: [.breakfast, .lunch, .dinner, .snack]), recipes: Self.pool + Self.snacks)
        #expect(plan.meals.count == 28)
        #expect(plan.issues.isEmpty)
        for day in week {
            #expect((2090.0...2310.0).contains(kcal(plan, on: day)))
        }
    }

    @Test func theSameSeedGivesTheSameMenu() {
        #expect(WeekMenuPlanner.plan(request(seed: 7), recipes: Self.pool) == WeekMenuPlanner.plan(request(seed: 7), recipes: Self.pool))
        #expect(WeekMenuPlanner.plan(request(seed: 7), recipes: Self.pool.reversed()) == WeekMenuPlanner.plan(request(seed: 7), recipes: Self.pool))
    }

    @Test func anotherSeedGivesAnotherMenu() {
        let menus = Set((1...5).map { seed in
            WeekMenuPlanner.plan(request(seed: UInt64(seed)), recipes: Self.pool).meals.map(\.recipeID)
        })
        #expect(menus.count > 1)
    }

    @Test func givesAnEmptyPlanWithoutDaysOrTarget() {
        var noDays = request()
        noDays.days = []
        #expect(WeekMenuPlanner.plan(noDays, recipes: Self.pool) == MenuPlan(meals: [], issues: []))
        var noTarget = request()
        noTarget.kcalTarget = 0
        #expect(WeekMenuPlanner.plan(noTarget, recipes: Self.pool) == MenuPlan(meals: [], issues: []))
    }
}
