import Foundation

/// One ingredient of a recipe, as written for the number of servings the recipe makes.
public struct MenuIngredient: Sendable, Equatable {
    public var productID: UUID?
    public var name: String
    public var quantity: Double
    /// "g", "ml", "piece", "tbsp" or "tsp", as in `recipe_ingredients.unit`.
    public var unit: String
    public var aisle: String

    public init(productID: UUID?, name: String, quantity: Double, unit: String, aisle: String) {
        self.productID = productID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
    }
}

/// A recipe on the menu: how many servings it makes as written, and how many are planned.
/// A leftover is a use like any other: its portion is cooked in the same batch.
public struct PlannedRecipeUse: Sendable, Equatable {
    public var recipeServings: Int
    public var plannedServings: Double
    public var ingredients: [MenuIngredient]

    public init(recipeServings: Int, plannedServings: Double, ingredients: [MenuIngredient]) {
        self.recipeServings = recipeServings
        self.plannedServings = plannedServings
        self.ingredients = ingredients
    }
}

public struct ShoppingLine: Sendable, Equatable {
    public var productID: UUID?
    public var name: String
    public var quantity: Double
    public var unit: String
    public var aisle: String

    public init(productID: UUID?, name: String, quantity: Double, unit: String, aisle: String) {
        self.productID = productID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
    }
}

public enum ShoppingListBuilder {
    /// The order of a walk through the shop; the values of `shopping_items.aisle`.
    public static let aisleOrder = ["produce", "bakery", "meat_fish", "dairy", "frozen", "pantry", "drinks", "household", "other"]

    /// One line per product and unit, with the quantities of the whole menu added up, in the
    /// order of the shop.
    public static func lines(for uses: [PlannedRecipeUse]) -> [ShoppingLine] {
        var order: [String] = []
        var lines: [String: ShoppingLine] = [:]
        for use in uses where use.recipeServings > 0 && use.plannedServings > 0 {
            let factor = use.plannedServings / Double(use.recipeServings)
            for ingredient in use.ingredients where ingredient.quantity > 0 {
                // The same product in another unit is another line: grams and pieces do not add up.
                let identity = ingredient.productID?.uuidString ?? normalized(ingredient.name)
                let key = identity + "|" + ingredient.unit
                if lines[key] == nil {
                    order.append(key)
                    lines[key] = ShoppingLine(
                        productID: ingredient.productID, name: ingredient.name.trimmingCharacters(in: .whitespaces),
                        quantity: 0, unit: ingredient.unit, aisle: ingredient.aisle
                    )
                }
                lines[key]?.quantity += ingredient.quantity * factor
            }
        }
        return order
            .compactMap { lines[$0] }
            .map { line in
                var rounded = line
                rounded.quantity = roundedUp(line.quantity, unit: line.unit)
                return rounded
            }
            .sorted { sortKey($0) < sortKey($1) }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Rounded up to what can be bought or measured: whole grams, millilitres and pieces, half spoons.
    private static func roundedUp(_ quantity: Double, unit: String) -> Double {
        let step = unit == "tbsp" || unit == "tsp" ? 0.5 : 1.0
        // The small margin keeps 125.00000001 from becoming 126.
        return (quantity / step - 1e-6).rounded(.up) * step
    }

    private static func sortKey(_ line: ShoppingLine) -> (Int, String, String) {
        (aisleOrder.firstIndex(of: line.aisle) ?? aisleOrder.count, normalized(line.name), line.unit)
    }
}
