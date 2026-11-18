import Foundation
import SwiftData
import FitlingCore

extension FitlingSchemaV1 {
    /// A product from the shared cache (`ownerID` is nil) or one the user made themselves.
    /// Only products the user has scanned, searched or logged are kept on the device.
    @Model
    final class Product {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID?
        var source: String
        var sourceID: String?
        /// Normalised with `Barcode.normalized`.
        var gtin: String?
        // JSON in `Data` on purpose: whether SwiftData on iOS 17 stores a dictionary attribute
        // reliably could not be verified without a Mac, and `Data` certainly works.
        var nameJSON: Data
        var brand: String?
        var searchName: String
        /// "g" or "ml": the nutrition values are per 100 of this.
        var quantityUnit: String
        var servingSize: Double?
        var servingLabel: String?
        // Nil means the source did not give the value. Without kcal a product cannot be logged yet.
        var kcal100: Double?
        var protein100: Double?
        var carbs100: Double?
        var sugars100: Double?
        var fat100: Double?
        var saturatedFat100: Double?
        var fiber100: Double?
        var salt100: Double?
        var imageURL: String?
        var isVerified: Bool
        var fetchedAt: Date?
        var updatedAt: Date
        var deletedAt: Date?
        /// Only ever true for the user's own products; shared rows are written by the backend.
        var needsPush: Bool

        init(id: UUID, ownerID: UUID?, source: String, name: LocalizedText, quantityUnit: String, updatedAt: Date) {
            self.id = id
            self.ownerID = ownerID
            self.source = source
            self.nameJSON = name.json
            self.searchName = ""
            self.quantityUnit = quantityUnit
            self.isVerified = false
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    @Model
    final class FoodEntry {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var consumedOn: String
        var meal: String
        var productID: UUID?
        var recipeID: UUID?
        // Name and values as they were when logged: updating a product must not change past days.
        var name: String
        var quantity: Double
        /// "g", "ml" or "serving".
        var quantityUnit: String
        var kcal: Double
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, userID: UUID, consumedOn: Day, meal: MealSlot, name: String,
            quantity: Double, quantityUnit: String, kcal: Double, updatedAt: Date
        ) {
            self.id = id
            self.userID = userID
            self.consumedOn = consumedOn.isoString
            self.meal = meal.rawValue
            self.name = name
            self.quantity = quantity
            self.quantityUnit = quantityUnit
            self.kcal = kcal
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class WaterEntry {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var consumedOn: String
        var amountMl: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, consumedOn: Day, amountMl: Int, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.consumedOn = consumedOn.isoString
            self.amountMl = amountMl
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    /// The same product can be a favourite twice after two devices added it offline; readers
    /// treat the rows as a set.
    @Model
    final class FavoriteProduct {
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
}

extension Product {
    var name: LocalizedText {
        get { LocalizedText(json: nameJSON) }
        set { nameJSON = newValue.json }
    }
}
