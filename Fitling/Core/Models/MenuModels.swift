import Foundation
import SwiftData
import FitlingCore

extension FitlingSchemaV1 {
    /// A shared recipe (`ownerID` is nil) or the user's own.
    @Model
    final class Recipe {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID?
        var titleJSON: Data
        /// Per language a list of steps: {"nl": ["Snijd de ui.", "Bak hem glazig."]}.
        var stepsJSON: Data
        var servings: Int
        var cookMinutes: Int
        var kcalPerServing: Double
        var proteinGPerServing: Double
        var carbsGPerServing: Double
        var fatGPerServing: Double
        var costCentsPerServing: Int?
        var keepsWell: Bool
        var mealSlots: [String]
        var tags: [String]
        var imageURL: String?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, ownerID: UUID?, title: LocalizedText, servings: Int, cookMinutes: Int,
            kcalPerServing: Double, proteinGPerServing: Double, carbsGPerServing: Double, fatGPerServing: Double,
            mealSlots: [MealSlot], updatedAt: Date
        ) {
            self.id = id
            self.ownerID = ownerID
            self.titleJSON = title.json
            self.stepsJSON = Data("{}".utf8)
            self.servings = servings
            self.cookMinutes = cookMinutes
            self.kcalPerServing = kcalPerServing
            self.proteinGPerServing = proteinGPerServing
            self.carbsGPerServing = carbsGPerServing
            self.fatGPerServing = fatGPerServing
            self.keepsWell = false
            self.mealSlots = mealSlots.map(\.rawValue)
            self.tags = []
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    @Model
    final class RecipeIngredient {
        @Attribute(.unique) var id: UUID
        var recipeID: UUID
        var ownerID: UUID?
        var productID: UUID?
        var nameJSON: Data
        var quantity: Double
        var unit: String
        var aisle: String
        var position: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, recipeID: UUID, ownerID: UUID?, name: LocalizedText,
            quantity: Double, unit: String, aisle: String, position: Int, updatedAt: Date
        ) {
            self.id = id
            self.recipeID = recipeID
            self.ownerID = ownerID
            self.nameJSON = name.json
            self.quantity = quantity
            self.unit = unit
            self.aisle = aisle
            self.position = position
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    /// One per user.
    @Model
    final class MenuPreferences {
        @Attribute(.unique) var userID: UUID
        var excludedTags: [String]
        var maxCookMinutes: Int?
        var budgetCents: Int?
        var mealPrep: Bool
        var mealSlots: [String]
        var updatedAt: Date
        var needsPush: Bool

        init(userID: UUID, updatedAt: Date) {
            self.userID = userID
            self.excludedTags = []
            self.mealPrep = false
            self.mealSlots = [MealSlot.breakfast, .lunch, .dinner].map(\.rawValue)
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class ExcludedIngredient {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var productID: UUID
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, productID: UUID, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.productID = productID
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class MealPlanEntry {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var plannedOn: String
        var meal: String
        var recipeID: UUID
        var servings: Double
        var isLeftover: Bool
        var isPinned: Bool
        /// Set once the meal has been logged, so one tap cannot log it twice.
        var loggedEntryID: UUID?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, meal: PlannedMeal, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.plannedOn = meal.day.isoString
            self.meal = meal.slot.rawValue
            self.recipeID = meal.recipeID
            self.servings = meal.servings
            self.isLeftover = meal.isLeftover
            self.isPinned = meal.isPinned
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }
}

extension Recipe {
    var title: LocalizedText {
        get { LocalizedText(json: titleJSON) }
        set { titleJSON = newValue.json }
    }

    var steps: [String: [String]] {
        get { (try? JSONDecoder().decode([String: [String]].self, from: stepsJSON)) ?? [:] }
        set { stepsJSON = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }

    /// The recipe as the week-menu planner sees it. Nil for a recipe without energy, which
    /// the planner could not scale.
    func plannerRecipe(ingredientIDs: Set<UUID>) -> PlannerRecipe? {
        guard kcalPerServing > 0 else { return nil }
        return PlannerRecipe(
            id: id, kcalPerServing: kcalPerServing, proteinPerServing: proteinGPerServing, cookMinutes: cookMinutes,
            costCentsPerServing: costCentsPerServing, slots: Set(mealSlots.compactMap(MealSlot.init(rawValue:))),
            tags: Set(tags), ingredientIDs: ingredientIDs, keepsWell: keepsWell
        )
    }
}

extension RecipeIngredient {
    var name: LocalizedText {
        get { LocalizedText(json: nameJSON) }
        set { nameJSON = newValue.json }
    }
}

extension MealPlanEntry {
    /// Nil when the stored values are not ones this app version knows.
    var plannedMeal: PlannedMeal? {
        guard let day = Day(isoString: plannedOn), let slot = MealSlot(rawValue: meal) else { return nil }
        return PlannedMeal(day: day, slot: slot, recipeID: recipeID, servings: servings, isLeftover: isLeftover, isPinned: isPinned)
    }
}
