import Foundation
import SwiftData
import FitlingCore

/// A row of `water_entries`: one glass, not a day total, so two devices simply add up.
struct WaterEntryRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var consumedOn: Day
    var amountMl: Int
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case consumedOn = "consumed_on"
        case amountMl = "amount_ml"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(consumedOn, forKey: .consumedOn)
        try container.encode(amountMl, forKey: .amountMl)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension WaterEntry: SyncableModel {
    static var tableName: String { "water_entries" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<WaterEntry> {
        FetchDescriptor(predicate: #Predicate<WaterEntry> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<WaterEntry> {
        FetchDescriptor(predicate: #Predicate<WaterEntry> { ids.contains($0.id) })
    }

    static func make(from record: WaterEntryRecord) -> WaterEntry {
        let entry = WaterEntry(id: record.id, userID: record.userID, consumedOn: record.consumedOn, amountMl: record.amountMl, updatedAt: record.updatedAt)
        entry.apply(record)
        return entry
    }

    var syncID: UUID { id }

    var record: WaterEntryRecord {
        WaterEntryRecord(
            id: id, userID: userID, consumedOn: Day(isoString: consumedOn) ?? Day(ordinal: 0), amountMl: amountMl,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: WaterEntryRecord) {
        userID = record.userID
        consumedOn = record.consumedOn.isoString
        amountMl = record.amountMl
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

/// A row of `favorite_products`.
struct FavoriteProductRecord: SyncRecord, Equatable {
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
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(productID, forKey: .productID)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension FavoriteProduct: SyncableModel {
    static var tableName: String { "favorite_products" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<FavoriteProduct> {
        FetchDescriptor(predicate: #Predicate<FavoriteProduct> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<FavoriteProduct> {
        FetchDescriptor(predicate: #Predicate<FavoriteProduct> { ids.contains($0.id) })
    }

    static func make(from record: FavoriteProductRecord) -> FavoriteProduct {
        let favorite = FavoriteProduct(id: record.id, userID: record.userID, productID: record.productID, updatedAt: record.updatedAt)
        favorite.apply(record)
        return favorite
    }

    var syncID: UUID { id }

    var record: FavoriteProductRecord {
        FavoriteProductRecord(id: id, userID: userID, productID: productID, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil)
    }

    func apply(_ record: FavoriteProductRecord) {
        userID = record.userID
        productID = record.productID
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
