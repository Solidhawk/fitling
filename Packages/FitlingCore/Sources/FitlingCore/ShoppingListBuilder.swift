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
        []
    }
}
