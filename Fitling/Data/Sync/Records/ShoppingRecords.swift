import Foundation
import SwiftData
import FitlingCore

// The shopping tables that sync like the others (TASKS 6.2). Members of a list have no
// `synced_at`; they go through `ListSharing` instead.

// MARK: - shopping_lists

struct ShoppingListRecord: SyncRecord, Equatable {
    var id: UUID
    var name: String
    var createdBy: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ShoppingList: SyncableModel {
    static var tableName: String { "shopping_lists" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<ShoppingList> {
        FetchDescriptor(predicate: #Predicate<ShoppingList> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ShoppingList> {
        FetchDescriptor(predicate: #Predicate<ShoppingList> { ids.contains($0.id) })
    }

    static func make(from record: ShoppingListRecord) -> ShoppingList {
        let list = ShoppingList(id: record.id, name: record.name, createdBy: record.createdBy ?? UUID(), updatedAt: record.updatedAt)
        list.apply(record)
        return list
    }

    var syncID: UUID { id }

    var record: ShoppingListRecord {
        ShoppingListRecord(id: id, name: name, createdBy: createdBy, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil)
    }

    func apply(_ record: ShoppingListRecord) {
        name = record.name
        createdBy = record.createdBy
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - shopping_items

struct ShoppingItemRecord: SyncRecord, Equatable {
    var id: UUID
    var listID: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var aisle: String
    var productID: UUID?
    var isChecked: Bool
    var source: String
    var updatedBy: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, aisle, source
        case listID = "list_id"
        case productID = "product_id"
        case isChecked = "is_checked"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(listID, forKey: .listID)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(aisle, forKey: .aisle)
        try c.encode(productID, forKey: .productID)
        try c.encode(isChecked, forKey: .isChecked)
        try c.encode(source, forKey: .source)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ShoppingItem: SyncableModel {
    static var tableName: String { "shopping_items" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<ShoppingItem> {
        FetchDescriptor(predicate: #Predicate<ShoppingItem> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ShoppingItem> {
        FetchDescriptor(predicate: #Predicate<ShoppingItem> { ids.contains($0.id) })
    }

    static func make(from record: ShoppingItemRecord) -> ShoppingItem {
        let item = ShoppingItem(
            id: record.id, listID: record.listID, name: record.name, aisle: record.aisle, source: record.source,
            updatedBy: record.updatedBy ?? UUID(), updatedAt: record.updatedAt
        )
        item.apply(record)
        return item
    }

    var syncID: UUID { id }

    var record: ShoppingItemRecord {
        ShoppingItemRecord(
            id: id, listID: listID, name: name, quantity: quantity, unit: unit, aisle: aisle, productID: productID,
            isChecked: isChecked, source: source, updatedBy: updatedBy, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ShoppingItemRecord) {
        listID = record.listID
        name = record.name
        quantity = record.quantity
        unit = record.unit
        aisle = record.aisle
        productID = record.productID
        isChecked = record.isChecked
        source = record.source
        updatedBy = record.updatedBy
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - favorite_supermarkets

struct FavoriteSupermarketRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var supermarketID: String
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case supermarketID = "supermarket_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(supermarketID, forKey: .supermarketID)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension FavoriteSupermarket: SyncableModel {
    static var tableName: String { "favorite_supermarkets" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<FavoriteSupermarket> {
        FetchDescriptor(predicate: #Predicate<FavoriteSupermarket> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<FavoriteSupermarket> {
        FetchDescriptor(predicate: #Predicate<FavoriteSupermarket> { ids.contains($0.id) })
    }

    static func make(from record: FavoriteSupermarketRecord) -> FavoriteSupermarket {
        let favorite = FavoriteSupermarket(id: record.id, userID: record.userID, supermarketID: record.supermarketID, updatedAt: record.updatedAt)
        favorite.apply(record)
        return favorite
    }

    var syncID: UUID { id }

    var record: FavoriteSupermarketRecord {
        FavoriteSupermarketRecord(id: id, userID: userID, supermarketID: supermarketID, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil)
    }

    func apply(_ record: FavoriteSupermarketRecord) {
        userID = record.userID
        supermarketID = record.supermarketID
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
