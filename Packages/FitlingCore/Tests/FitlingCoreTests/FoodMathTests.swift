import Foundation
import Testing
@testable import FitlingCore

@Suite struct FoodMathTests {
    let peanutButter = NutrientsPer100(kcal: 600, proteinG: 25, carbsG: 12, fatG: 50)

    @Test func gramsScaleLinearly() {
        let result = FoodMath.nutrients(per100: peanutButter, quantity: 30, unit: .gram, servingSize: nil)
        #expect(result == Nutrients(kcal: 180, proteinG: 7.5, carbsG: 3.6, fatG: 15))
    }

    @Test func millilitresWorkLikeGrams() {
        let milk = NutrientsPer100(kcal: 46, proteinG: 3.4, carbsG: 4.8, fatG: 1.5)
        let result = FoodMath.nutrients(per100: milk, quantity: 250, unit: .millilitre, servingSize: nil)
        #expect(result == Nutrients(kcal: 115, proteinG: 8.5, carbsG: 12, fatG: 3.8))
    }

    @Test func servingsUseTheServingSize() {
        let result = FoodMath.nutrients(per100: peanutButter, quantity: 2, unit: .serving, servingSize: 15)
        #expect(result == Nutrients(kcal: 180, proteinG: 7.5, carbsG: 3.6, fatG: 15))
        #expect(FoodMath.amount(quantity: 2, unit: .serving, servingSize: 15) == 30)
    }

    @Test func servingsWithoutAServingSizeAreNotPossible() {
        #expect(FoodMath.nutrients(per100: peanutButter, quantity: 1, unit: .serving, servingSize: nil) == nil)
        #expect(FoodMath.nutrients(per100: peanutButter, quantity: 1, unit: .serving, servingSize: 0) == nil)
    }

    @Test func aProductWithoutKcalCannotBeLogged() {
        let unknown = NutrientsPer100(kcal: nil, proteinG: 25, carbsG: 12, fatG: 50)
        #expect(FoodMath.nutrients(per100: unknown, quantity: 30, unit: .gram, servingSize: nil) == nil)
    }

    @Test func anUnknownMacroStaysUnknown() {
        let partial = NutrientsPer100(kcal: 600, proteinG: nil, carbsG: 12, fatG: nil)
        let result = FoodMath.nutrients(per100: partial, quantity: 30, unit: .gram, servingSize: nil)
        #expect(result == Nutrients(kcal: 180, proteinG: nil, carbsG: 3.6, fatG: nil))
    }

    @Test func aQuantityThatIsNotPositiveGivesNothing() {
        #expect(FoodMath.nutrients(per100: peanutButter, quantity: 0, unit: .gram, servingSize: nil) == nil)
        #expect(FoodMath.nutrients(per100: peanutButter, quantity: -5, unit: .gram, servingSize: nil) == nil)
        #expect(FoodMath.nutrients(per100: peanutButter, quantity: .nan, unit: .gram, servingSize: nil) == nil)
    }

    @Test func roundsToOneDecimal() {
        let apple = NutrientsPer100(kcal: 52.4, proteinG: 0.26, carbsG: 13.81, fatG: 0.17)
        let result = FoodMath.nutrients(per100: apple, quantity: 33, unit: .gram, servingSize: nil)
        #expect(result == Nutrients(kcal: 17.3, proteinG: 0.1, carbsG: 4.6, fatG: 0.1))
    }

    @Test func kilojoulesBecomeKilocalories() {
        #expect(abs(FoodMath.kcal(fromKilojoules: 2092) - 500) < 0.0001)
        #expect(FoodMath.kcal(fromKilojoules: 0) == 0)
    }

    @Test func aLabelThatFitsItsMacrosIsConsistent() {
        // 4 × 25 + 4 × 12 + 9 × 50 = 598
        #expect(FoodMath.isConsistent(kcal: 600, proteinG: 25, carbsG: 12, fatG: 50))
        #expect(FoodMath.isConsistent(kcal: 250, proteinG: 10, carbsG: 30, fatG: 10))
    }

    @Test func aLabelThatDoesNotAddUpIsInconsistent() {
        // The macros give 420 kcal, the label says 100.
        #expect(FoodMath.isConsistent(kcal: 100, proteinG: 10, carbsG: 50, fatG: 20) == false)
        // The label says 500, the macros give 230.
        #expect(FoodMath.isConsistent(kcal: 500, proteinG: 10, carbsG: 30, fatG: 10) == false)
    }

    @Test func aSmallDifferenceOnALowCalorieProductIsFine() {
        // 29.5 against 20 is 47 % more, but only 9.5 kcal.
        #expect(FoodMath.isConsistent(kcal: 20, proteinG: 1, carbsG: 3, fatG: 1.5))
    }

    @Test func dayTotalsCountUnknownAsZeroAndReportIt() {
        let totals = FoodMath.totals([
            Nutrients(kcal: 180, proteinG: 7.5, carbsG: nil, fatG: 15),
            Nutrients(kcal: 300, proteinG: nil, carbsG: 40, fatG: 10),
        ])
        #expect(totals.kcal == 480)
        #expect(totals.proteinG == 7.5)
        #expect(totals.carbsG == 40)
        #expect(totals.fatG == 25)
        #expect(totals.entryCount == 2)
        #expect(totals.unknownProtein == 1)
        #expect(totals.unknownCarbs == 1)
        #expect(totals.unknownFat == 0)
    }

    @Test func anEmptyDayIsAllZero() {
        #expect(FoodMath.totals([]) == DayTotals())
    }

    @Test func unitsMatchTheDatabase() {
        #expect(QuantityUnit.allCases.map(\.rawValue) == ["g", "ml", "serving"])
    }
}

@Suite struct ShoppingListBuilderTests {
    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    let onion = MenuIngredient(productID: id(1), name: "Ui", quantity: 100, unit: "g", aisle: "produce")

    @Test func scalesByThePlannedServings() {
        let rice = MenuIngredient(productID: Self.id(2), name: "Rijst", quantity: 400, unit: "g", aisle: "pantry")
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 4, plannedServings: 1.5, ingredients: [rice])])
        #expect(lines == [ShoppingLine(productID: Self.id(2), name: "Rijst", quantity: 150, unit: "g", aisle: "pantry")])
    }

    @Test func sumsTheSameProductAcrossRecipes() {
        var bigOnion = onion
        bigOnion.quantity = 150
        let lines = ShoppingListBuilder.lines(for: [
            PlannedRecipeUse(recipeServings: 4, plannedServings: 2, ingredients: [onion]),
            PlannedRecipeUse(recipeServings: 2, plannedServings: 1, ingredients: [bigOnion]),
        ])
        #expect(lines == [ShoppingLine(productID: Self.id(1), name: "Ui", quantity: 125, unit: "g", aisle: "produce")])
    }

    @Test func aLeftoverPortionIsCookedInTheSameBatch() {
        let stew = MenuIngredient(productID: Self.id(3), name: "Rundvlees", quantity: 400, unit: "g", aisle: "meat_fish")
        let lines = ShoppingListBuilder.lines(for: [
            PlannedRecipeUse(recipeServings: 4, plannedServings: 1.25, ingredients: [stew]),
            PlannedRecipeUse(recipeServings: 4, plannedServings: 1, ingredients: [stew]),
        ])
        #expect(lines.map(\.quantity) == [225])
    }

    @Test func keepsDifferentUnitsApart() {
        var whole = onion
        whole.quantity = 1
        whole.unit = "piece"
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 1, plannedServings: 1, ingredients: [onion, whole])])
        #expect(lines.map(\.unit) == ["g", "piece"])
        #expect(lines.map(\.quantity) == [100, 1])
    }

    @Test func mergesIngredientsWithoutAProductByName() {
        let salt = MenuIngredient(productID: nil, name: "Zout", quantity: 1, unit: "tsp", aisle: "pantry")
        let sameSalt = MenuIngredient(productID: nil, name: " zout", quantity: 0.5, unit: "tsp", aisle: "pantry")
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 1, plannedServings: 1, ingredients: [salt, sameSalt])])
        #expect(lines == [ShoppingLine(productID: nil, name: "Zout", quantity: 1.5, unit: "tsp", aisle: "pantry")])
    }

    /// Lemon juice in teaspoons in one recipe and in tablespoons in another is one line (UNFORGET S24).
    @Test func teaspoonsAndTablespoonsOfTheSameProductAddUp() {
        let teaspoon = MenuIngredient(productID: nil, name: "Citroensap", quantity: 1, unit: "tsp", aisle: "produce")
        let tablespoons = MenuIngredient(productID: nil, name: "Citroensap", quantity: 2, unit: "tbsp", aisle: "produce")
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 1, plannedServings: 1, ingredients: [teaspoon, tablespoons])])
        // A teaspoon is a third of a tablespoon: 2⅓ tablespoons, rounded up to half a spoon.
        #expect(lines == [ShoppingLine(productID: nil, name: "Citroensap", quantity: 2.5, unit: "tbsp", aisle: "produce")])
    }

    @Test func roundsUpToWhatCanBeBought() {
        let ingredients = [
            MenuIngredient(productID: Self.id(1), name: "Ui", quantity: 1, unit: "piece", aisle: "produce"),
            MenuIngredient(productID: Self.id(2), name: "Rijst", quantity: 100, unit: "g", aisle: "pantry"),
            MenuIngredient(productID: Self.id(4), name: "Olie", quantity: 1, unit: "tbsp", aisle: "pantry"),
        ]
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 3, plannedServings: 1, ingredients: ingredients)])
        // A third of an onion is one onion, 33.3 g is 34 g, a third of a spoon is half a spoon.
        #expect(lines.map(\.quantity) == [1, 0.5, 34])
    }

    @Test func followsTheOrderOfTheShopThenTheName() {
        let ingredients = [
            MenuIngredient(productID: Self.id(5), name: "Yoghurt", quantity: 200, unit: "g", aisle: "dairy"),
            MenuIngredient(productID: Self.id(2), name: "rijst", quantity: 100, unit: "g", aisle: "pantry"),
            MenuIngredient(productID: Self.id(6), name: "Tomaat", quantity: 2, unit: "piece", aisle: "produce"),
            MenuIngredient(productID: Self.id(7), name: "Bonen", quantity: 240, unit: "g", aisle: "pantry"),
            MenuIngredient(productID: Self.id(8), name: "Kaarsen", quantity: 1, unit: "piece", aisle: "onbekend schap"),
            MenuIngredient(productID: Self.id(1), name: "Ui", quantity: 1, unit: "piece", aisle: "produce"),
        ]
        let lines = ShoppingListBuilder.lines(for: [PlannedRecipeUse(recipeServings: 1, plannedServings: 1, ingredients: ingredients)])
        #expect(lines.map(\.name) == ["Tomaat", "Ui", "Yoghurt", "Bonen", "rijst", "Kaarsen"])
    }

    @Test func leavesOutWhatCannotBeScaled() {
        let lines = ShoppingListBuilder.lines(for: [
            PlannedRecipeUse(recipeServings: 0, plannedServings: 1, ingredients: [onion]),
            PlannedRecipeUse(recipeServings: 2, plannedServings: 0, ingredients: [onion]),
        ])
        #expect(lines.isEmpty)
    }
}
