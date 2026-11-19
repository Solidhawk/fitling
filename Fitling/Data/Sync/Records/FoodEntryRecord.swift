import Foundation
import SwiftData
import FitlingCore

/// A row of `food_entries`: what was eaten, with the name and values as they were when logged.
struct FoodEntryRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var consumedOn: Day
    var meal: String
    var productID: UUID?
    var recipeID: UUID?
    var name: String
    var quantity: Double
    var quantityUnit: String
    var kcal: Double
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case consumedOn = "consumed_on"
        case meal
        case productID = "product_id"
        case recipeID = "recipe_id"
        case name
        case quantity
        case quantityUnit = "quantity_unit"
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    /// No `synced_at`, and every empty value as null (see `ProfileRecord.encode(to:)`).
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(consumedOn, forKey: .consumedOn)
        try container.encode(meal, forKey: .meal)
        try container.encode(productID, forKey: .productID)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(quantityUnit, forKey: .quantityUnit)
        try container.encode(kcal, forKey: .kcal)
        try container.encode(proteinG, forKey: .proteinG)
        try container.encode(carbsG, forKey: .carbsG)
        try container.encode(fatG, forKey: .fatG)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension FoodEntry: SyncableModel {
    static var tableName: String { "food_entries" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<FoodEntry> {
        FetchDescriptor(predicate: #Predicate<FoodEntry> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<FoodEntry> {
        FetchDescriptor(predicate: #Predicate<FoodEntry> { ids.contains($0.id) })
    }

    static func make(from record: FoodEntryRecord) -> FoodEntry {
        let entry = FoodEntry(
            id: record.id, userID: record.userID, consumedOn: record.consumedOn, meal: MealSlot(rawValue: record.meal) ?? .snack,
            name: record.name, quantity: record.quantity, quantityUnit: record.quantityUnit, kcal: record.kcal, updatedAt: record.updatedAt
        )
        entry.apply(record)
        return entry
    }

    var syncID: UUID { id }

    var record: FoodEntryRecord {
        FoodEntryRecord(
            id: id, userID: userID, consumedOn: Day(isoString: consumedOn) ?? Day(ordinal: 0), meal: meal,
            productID: productID, recipeID: recipeID, name: name, quantity: quantity, quantityUnit: quantityUnit,
            kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: FoodEntryRecord) {
        userID = record.userID
        consumedOn = record.consumedOn.isoString
        // The server's own text, also a meal a newer app version knows and this one does not.
        meal = record.meal
        productID = record.productID
        recipeID = record.recipeID
        name = record.name
        quantity = record.quantity
        quantityUnit = record.quantityUnit
        kcal = record.kcal
        proteinG = record.proteinG
        carbsG = record.carbsG
        fatG = record.fatG
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
