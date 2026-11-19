import Foundation
import SwiftData

extension FitlingSchemaV1 {
    @Model
    final class ShoppingList {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdBy: UUID?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, name: String, createdBy: UUID, updatedAt: Date) {
            self.id = id
            self.name = name
            self.createdBy = createdBy
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class ShoppingListMember {
        /// The table's key is (list, user); SwiftData needs one value to keep a row unique.
        @Attribute(.unique) var key: String
        var listID: UUID
        var userID: UUID
        var role: String
        var displayName: String
        var joinedAt: Date
        var needsPush: Bool

        init(listID: UUID, userID: UUID, role: String, displayName: String, joinedAt: Date) {
            self.key = "\(listID.uuidString)|\(userID.uuidString)"
            self.listID = listID
            self.userID = userID
            self.role = role
            self.displayName = displayName
            self.joinedAt = joinedAt
            self.needsPush = true
        }
    }

    @Model
    final class ShoppingItem {
        @Attribute(.unique) var id: UUID
        var listID: UUID
        var name: String
        var quantity: Double?
        var unit: String?
        var aisle: String
        var productID: UUID?
        var isChecked: Bool
        /// "menu" for an item the week menu put on the list; those are replaced when the menu changes.
        var source: String
        var updatedBy: UUID?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, listID: UUID, name: String, aisle: String, source: String, updatedBy: UUID, updatedAt: Date) {
            self.id = id
            self.listID = listID
            self.name = name
            self.aisle = aisle
            self.isChecked = false
            self.source = source
            self.updatedBy = updatedBy
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    /// Read-only: written by the backend.
    @Model
    final class Supermarket {
        @Attribute(.unique) var id: String
        var name: String
        var updatedAt: Date

        init(id: String, name: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.updatedAt = updatedAt
        }
    }

    /// Read-only: written by the backend's offer job. Matching with the list happens on the device.
    @Model
    final class Offer {
        @Attribute(.unique) var id: UUID
        var supermarketID: String
        var externalID: String
        var title: String
        var searchTitle: String
        var brand: String?
        var gtin: String?
        var quantityValue: Double?
        var quantityUnit: String?
        var priceCents: Int
        var regularPriceCents: Int?
        var promoLabel: String?
        var validFrom: String
        var validTo: String
        var imageURL: String?
        var fetchedAt: Date

        init(
            id: UUID, supermarketID: String, externalID: String, title: String, searchTitle: String,
            priceCents: Int, validFrom: String, validTo: String, fetchedAt: Date
        ) {
            self.id = id
            self.supermarketID = supermarketID
            self.externalID = externalID
            self.title = title
            self.searchTitle = searchTitle
            self.priceCents = priceCents
            self.validFrom = validFrom
            self.validTo = validTo
            self.fetchedAt = fetchedAt
        }
    }

    @Model
    final class FavoriteSupermarket {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var supermarketID: String
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, supermarketID: String, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.supermarketID = supermarketID
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }
}
