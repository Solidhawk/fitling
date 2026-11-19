import Foundation
import SwiftData
import FitlingCore

// The recipe and week-menu tables (TASKS 5.1–5.4). Each record writes every column itself:
// `synced_at` belongs to the server and is never sent, and an empty value goes as null.

// MARK: - recipes

struct RecipeRecord: SyncRecord, Equatable {
    var id: UUID
    var ownerID: UUID?
    var title: LocalizedText
    var steps: [String: [String]]
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
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, steps, servings, tags
        case ownerID = "owner_id"
        case cookMinutes = "cook_minutes"
        case kcalPerServing = "kcal_per_serving"
        case proteinGPerServing = "protein_g_per_serving"
        case carbsGPerServing = "carbs_g_per_serving"
        case fatGPerServing = "fat_g_per_serving"
        case costCentsPerServing = "cost_cents_per_serving"
        case keepsWell = "keeps_well"
        case mealSlots = "meal_slots"
        case imageURL = "image_url"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(title, forKey: .title)
        try c.encode(steps, forKey: .steps)
        try c.encode(servings, forKey: .servings)
        try c.encode(cookMinutes, forKey: .cookMinutes)
        try c.encode(kcalPerServing, forKey: .kcalPerServing)
        try c.encode(proteinGPerServing, forKey: .proteinGPerServing)
        try c.encode(carbsGPerServing, forKey: .carbsGPerServing)
        try c.encode(fatGPerServing, forKey: .fatGPerServing)
        try c.encode(costCentsPerServing, forKey: .costCentsPerServing)
        try c.encode(keepsWell, forKey: .keepsWell)
        try c.encode(mealSlots, forKey: .mealSlots)
        try c.encode(tags, forKey: .tags)
        try c.encode(imageURL, forKey: .imageURL)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension Recipe: SyncableModel {
    static var tableName: String { "recipes" }
    static var keyColumn: String { "id" }
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<Recipe> {
        FetchDescriptor(predicate: #Predicate<Recipe> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<Recipe> {
        FetchDescriptor(predicate: #Predicate<Recipe> { ids.contains($0.id) })
    }

    static func make(from record: RecipeRecord) -> Recipe {
        let recipe = Recipe(
            id: record.id, ownerID: record.ownerID, title: record.title, servings: record.servings, cookMinutes: record.cookMinutes,
            kcalPerServing: record.kcalPerServing, proteinGPerServing: record.proteinGPerServing,
            carbsGPerServing: record.carbsGPerServing, fatGPerServing: record.fatGPerServing, mealSlots: [], updatedAt: record.updatedAt
        )
        recipe.apply(record)
        return recipe
    }

    var syncID: UUID { id }

    var record: RecipeRecord {
        RecipeRecord(
            id: id, ownerID: ownerID, title: title, steps: steps, servings: servings, cookMinutes: cookMinutes,
            kcalPerServing: kcalPerServing, proteinGPerServing: proteinGPerServing, carbsGPerServing: carbsGPerServing,
            fatGPerServing: fatGPerServing, costCentsPerServing: costCentsPerServing, keepsWell: keepsWell,
            mealSlots: mealSlots, tags: tags, imageURL: imageURL, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: RecipeRecord) {
        ownerID = record.ownerID
        title = record.title
        steps = record.steps
        servings = record.servings
        cookMinutes = record.cookMinutes
        kcalPerServing = record.kcalPerServing
        proteinGPerServing = record.proteinGPerServing
        carbsGPerServing = record.carbsGPerServing
        fatGPerServing = record.fatGPerServing
        costCentsPerServing = record.costCentsPerServing
        keepsWell = record.keepsWell
        mealSlots = record.mealSlots
        tags = record.tags
        imageURL = record.imageURL
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - recipe_ingredients

struct RecipeIngredientRecord: SyncRecord, Equatable {
    var id: UUID
    var recipeID: UUID
    var ownerID: UUID?
    var productID: UUID?
    var name: LocalizedText
    var quantity: Double
    var unit: String
    var aisle: String
    var position: Int
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, aisle, position
        case recipeID = "recipe_id"
        case ownerID = "owner_id"
        case productID = "product_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(recipeID, forKey: .recipeID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(productID, forKey: .productID)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(aisle, forKey: .aisle)
        try c.encode(position, forKey: .position)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension RecipeIngredient: SyncableModel {
    static var tableName: String { "recipe_ingredients" }
    static var keyColumn: String { "id" }
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<RecipeIngredient> {
        FetchDescriptor(predicate: #Predicate<RecipeIngredient> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<RecipeIngredient> {
        FetchDescriptor(predicate: #Predicate<RecipeIngredient> { ids.contains($0.id) })
    }

    static func make(from record: RecipeIngredientRecord) -> RecipeIngredient {
        let ingredient = RecipeIngredient(
            id: record.id, recipeID: record.recipeID, ownerID: record.ownerID, name: record.name, quantity: record.quantity,
            unit: record.unit, aisle: record.aisle, position: record.position, updatedAt: record.updatedAt
        )
        ingredient.apply(record)
        return ingredient
    }

    var syncID: UUID { id }

    var record: RecipeIngredientRecord {
        RecipeIngredientRecord(
            id: id, recipeID: recipeID, ownerID: ownerID, productID: productID, name: name, quantity: quantity, unit: unit,
            aisle: aisle, position: position, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: RecipeIngredientRecord) {
        recipeID = record.recipeID
        ownerID = record.ownerID
        productID = record.productID
        name = record.name
        quantity = record.quantity
        unit = record.unit
        aisle = record.aisle
        position = record.position
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - menu_preferences

struct MenuPreferencesRecord: SyncRecord, Equatable {
    var userID: UUID
    var excludedTags: [String]
    var maxCookMinutes: Int?
    var budgetCents: Int?
    var mealPrep: Bool
    var mealSlots: [String]
    var updatedAt: Date
    var syncedAt: Date?

    var id: UUID { userID }
    var deletedAt: Date? { nil }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case excludedTags = "excluded_tags"
        case maxCookMinutes = "max_cook_minutes"
        case budgetCents = "budget_cents"
        case mealPrep = "meal_prep"
        case mealSlots = "meal_slots"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(excludedTags, forKey: .excludedTags)
        try c.encode(maxCookMinutes, forKey: .maxCookMinutes)
        try c.encode(budgetCents, forKey: .budgetCents)
        try c.encode(mealPrep, forKey: .mealPrep)
        try c.encode(mealSlots, forKey: .mealSlots)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension MenuPreferences: SyncableModel {
    static var tableName: String { "menu_preferences" }
    static var keyColumn: String { "user_id" }

    static var pending: FetchDescriptor<MenuPreferences> {
        FetchDescriptor(predicate: #Predicate<MenuPreferences> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<MenuPreferences> {
        FetchDescriptor(predicate: #Predicate<MenuPreferences> { ids.contains($0.userID) })
    }

    static func make(from record: MenuPreferencesRecord) -> MenuPreferences {
        let preferences = MenuPreferences(userID: record.userID, updatedAt: record.updatedAt)
        preferences.apply(record)
        return preferences
    }

    var syncID: UUID { userID }
    var deletedAt: Date? { nil }

    var record: MenuPreferencesRecord {
        MenuPreferencesRecord(
            userID: userID, excludedTags: excludedTags, maxCookMinutes: maxCookMinutes, budgetCents: budgetCents,
            mealPrep: mealPrep, mealSlots: mealSlots, updatedAt: updatedAt, syncedAt: nil
        )
    }

    func apply(_ record: MenuPreferencesRecord) {
        excludedTags = record.excludedTags
        maxCookMinutes = record.maxCookMinutes
        budgetCents = record.budgetCents
        mealPrep = record.mealPrep
        mealSlots = record.mealSlots
        updatedAt = record.updatedAt
        needsPush = false
    }
}

// MARK: - excluded_ingredients

struct ExcludedIngredientRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var productID: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(productID, forKey: .productID)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ExcludedIngredient: SyncableModel {
    static var tableName: String { "excluded_ingredients" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<ExcludedIngredient> {
        FetchDescriptor(predicate: #Predicate<ExcludedIngredient> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ExcludedIngredient> {
        FetchDescriptor(predicate: #Predicate<ExcludedIngredient> { ids.contains($0.id) })
    }

    static func make(from record: ExcludedIngredientRecord) -> ExcludedIngredient {
        let excluded = ExcludedIngredient(id: record.id, userID: record.userID, productID: record.productID, updatedAt: record.updatedAt)
        excluded.apply(record)
        return excluded
    }

    var syncID: UUID { id }

    var record: ExcludedIngredientRecord {
        ExcludedIngredientRecord(id: id, userID: userID, productID: productID, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil)
    }

    func apply(_ record: ExcludedIngredientRecord) {
        userID = record.userID
        productID = record.productID
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - meal_plan_entries

struct MealPlanEntryRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var plannedOn: Day
    var meal: String
    var recipeID: UUID
    var servings: Double
    var isLeftover: Bool
    var isPinned: Bool
    var loggedEntryID: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, meal, servings
        case userID = "user_id"
        case plannedOn = "planned_on"
        case recipeID = "recipe_id"
        case isLeftover = "is_leftover"
        case isPinned = "is_pinned"
        case loggedEntryID = "logged_entry_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(plannedOn, forKey: .plannedOn)
        try c.encode(meal, forKey: .meal)
        try c.encode(recipeID, forKey: .recipeID)
        try c.encode(servings, forKey: .servings)
        try c.encode(isLeftover, forKey: .isLeftover)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(loggedEntryID, forKey: .loggedEntryID)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension MealPlanEntry: SyncableModel {
    static var tableName: String { "meal_plan_entries" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<MealPlanEntry> {
        FetchDescriptor(predicate: #Predicate<MealPlanEntry> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<MealPlanEntry> {
        FetchDescriptor(predicate: #Predicate<MealPlanEntry> { ids.contains($0.id) })
    }

    static func make(from record: MealPlanEntryRecord) -> MealPlanEntry {
        let entry = MealPlanEntry(
            id: record.id, userID: record.userID,
            meal: PlannedMeal(day: record.plannedOn, slot: MealSlot(rawValue: record.meal) ?? .dinner, recipeID: record.recipeID, servings: record.servings),
            updatedAt: record.updatedAt
        )
        entry.apply(record)
        return entry
    }

    var syncID: UUID { id }

    var record: MealPlanEntryRecord {
        MealPlanEntryRecord(
            id: id, userID: userID, plannedOn: Day(isoString: plannedOn) ?? Day(ordinal: 0), meal: meal, recipeID: recipeID,
            servings: servings, isLeftover: isLeftover, isPinned: isPinned, loggedEntryID: loggedEntryID,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: MealPlanEntryRecord) {
        userID = record.userID
        plannedOn = record.plannedOn.isoString
        meal = record.meal
        recipeID = record.recipeID
        servings = record.servings
        isLeftover = record.isLeftover
        isPinned = record.isPinned
        loggedEntryID = record.loggedEntryID
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
