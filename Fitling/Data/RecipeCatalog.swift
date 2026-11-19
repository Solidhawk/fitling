import Foundation
import SwiftData
import FitlingCore

/// The shared recipes, as `Resources/RecipeCatalog.json` holds them. `scripts/recipe-seed.mjs`
/// makes that file and the server seed from the same source, with the energy per serving worked
/// out from the ingredients (USDA SR Legacy). The photos are in the asset catalog under Recipes.
struct RecipeCatalog: Decodable {
    struct PhotoCredit: Decodable, Equatable {
        let author: String
        let licence: String
        let page: String
    }

    struct IngredientEntry: Decodable {
        let id: UUID
        let name: LocalizedText
        let quantity: Double
        let unit: String
        let aisle: String
        let position: Int
    }

    struct RecipeEntry: Decodable {
        let id: UUID
        let title: LocalizedText
        let steps: [String: [String]]
        let servings: Int
        let cookMinutes: Int
        let kcalPerServing: Double
        let proteinGPerServing: Double
        let carbsGPerServing: Double
        let fatGPerServing: Double
        let keepsWell: Bool
        let mealSlots: [String]
        let tags: [String]
        let photoCredit: PhotoCredit
        let ingredients: [IngredientEntry]
    }

    let version: Int
    let recipes: [RecipeEntry]

    static func bundled(in bundle: Bundle = .main) -> RecipeCatalog? {
        guard let url = bundle.url(forResource: "RecipeCatalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecipeCatalog.self, from: data)
    }

    /// Who made the photo of a shared recipe and under which licence, for the credit line.
    func credit(for recipeID: UUID) -> PhotoCredit? {
        recipes.first { $0.id == recipeID }?.photoCredit
    }

    /// Puts the shared recipes on the device or brings them up to date; cheap when nothing changed.
    @MainActor
    func install(into context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) {
        let key = "fitling.recipeCatalogVersion"
        let shared = (try? context.fetchCount(FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.ownerID == nil }))) ?? 0
        guard defaults.integer(forKey: key) < version || shared < recipes.count else { return }

        let recipesByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).map { ($0.id, $0) })
        let ingredientsByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<RecipeIngredient>())) ?? []).map { ($0.id, $0) })
        for entry in recipes {
            let recipe = recipesByID[entry.id] ?? {
                let made = Recipe(
                    id: entry.id, ownerID: nil, title: entry.title, servings: entry.servings, cookMinutes: entry.cookMinutes,
                    kcalPerServing: entry.kcalPerServing, proteinGPerServing: entry.proteinGPerServing,
                    carbsGPerServing: entry.carbsGPerServing, fatGPerServing: entry.fatGPerServing, mealSlots: [], updatedAt: now
                )
                context.insert(made)
                return made
            }()
            recipe.title = entry.title
            recipe.steps = entry.steps
            recipe.servings = entry.servings
            recipe.cookMinutes = entry.cookMinutes
            recipe.kcalPerServing = entry.kcalPerServing
            recipe.proteinGPerServing = entry.proteinGPerServing
            recipe.carbsGPerServing = entry.carbsGPerServing
            recipe.fatGPerServing = entry.fatGPerServing
            recipe.keepsWell = entry.keepsWell
            recipe.mealSlots = entry.mealSlots
            recipe.tags = entry.tags
            recipe.deletedAt = nil
            recipe.needsPush = false
            for item in entry.ingredients {
                let ingredient = ingredientsByID[item.id] ?? {
                    let made = RecipeIngredient(
                        id: item.id, recipeID: entry.id, ownerID: nil, name: item.name, quantity: item.quantity,
                        unit: item.unit, aisle: item.aisle, position: item.position, updatedAt: now
                    )
                    context.insert(made)
                    return made
                }()
                ingredient.name = item.name
                ingredient.quantity = item.quantity
                ingredient.unit = item.unit
                ingredient.aisle = item.aisle
                ingredient.position = item.position
                ingredient.needsPush = false
            }
        }
        try? context.save()
        defaults.set(version, forKey: key)
    }
}
