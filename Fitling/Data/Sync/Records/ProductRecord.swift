import Foundation
import SwiftData
import FitlingCore

/// A row of `products`. Only the user's own products sync; shared rows come from
/// `lookup-product` or a search and are never pushed.
struct ProductRecord: SyncRecord, Equatable {
    var id: UUID
    var ownerID: UUID?
    var source: String
    var sourceID: String?
    var gtin: String?
    var name: LocalizedText
    var brand: String?
    var searchName: String
    var quantityUnit: String
    var servingSize: Double?
    var servingLabel: String?
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
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case source
        case sourceID = "source_id"
        case gtin
        case name
        case brand
        case searchName = "search_name"
        case quantityUnit = "quantity_unit"
        case servingSize = "serving_size"
        case servingLabel = "serving_label"
        case kcal100 = "kcal_100"
        case protein100 = "protein_100"
        case carbs100 = "carbs_100"
        case sugars100 = "sugars_100"
        case fat100 = "fat_100"
        case saturatedFat100 = "saturated_fat_100"
        case fiber100 = "fiber_100"
        case salt100 = "salt_100"
        case imageURL = "image_url"
        case isVerified = "is_verified"
        case fetchedAt = "fetched_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    /// No `synced_at`, and every empty value as null (see `ProfileRecord.encode(to:)`).
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(source, forKey: .source)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(gtin, forKey: .gtin)
        try container.encode(name, forKey: .name)
        try container.encode(brand, forKey: .brand)
        try container.encode(searchName, forKey: .searchName)
        try container.encode(quantityUnit, forKey: .quantityUnit)
        try container.encode(servingSize, forKey: .servingSize)
        try container.encode(servingLabel, forKey: .servingLabel)
        try container.encode(kcal100, forKey: .kcal100)
        try container.encode(protein100, forKey: .protein100)
        try container.encode(carbs100, forKey: .carbs100)
        try container.encode(sugars100, forKey: .sugars100)
        try container.encode(fat100, forKey: .fat100)
        try container.encode(saturatedFat100, forKey: .saturatedFat100)
        try container.encode(fiber100, forKey: .fiber100)
        try container.encode(salt100, forKey: .salt100)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encode(isVerified, forKey: .isVerified)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension Product: SyncableModel {
    static var tableName: String { "products" }
    static var keyColumn: String { "id" }
    /// The shared cache is far too large for a device; only the user's own rows are pulled.
    static var ownerColumn: String? { "owner_id" }

    /// A shared row never goes up, also if a bug ever set its flag.
    static var pending: FetchDescriptor<Product> {
        FetchDescriptor(predicate: #Predicate<Product> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<Product> {
        FetchDescriptor(predicate: #Predicate<Product> { ids.contains($0.id) })
    }

    static func make(from record: ProductRecord) -> Product {
        let product = Product(
            id: record.id, ownerID: record.ownerID, source: record.source, name: record.name,
            quantityUnit: record.quantityUnit, updatedAt: record.updatedAt
        )
        product.apply(record)
        return product
    }

    var syncID: UUID { id }

    var record: ProductRecord {
        ProductRecord(
            id: id, ownerID: ownerID, source: source, sourceID: sourceID, gtin: gtin, name: name, brand: brand,
            searchName: searchName, quantityUnit: quantityUnit, servingSize: servingSize, servingLabel: servingLabel,
            kcal100: kcal100, protein100: protein100, carbs100: carbs100, sugars100: sugars100, fat100: fat100,
            saturatedFat100: saturatedFat100, fiber100: fiber100, salt100: salt100, imageURL: imageURL,
            isVerified: isVerified, fetchedAt: fetchedAt, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ProductRecord) {
        ownerID = record.ownerID
        source = record.source
        sourceID = record.sourceID
        gtin = record.gtin
        name = record.name
        brand = record.brand
        searchName = record.searchName
        quantityUnit = record.quantityUnit
        servingSize = record.servingSize
        servingLabel = record.servingLabel
        kcal100 = record.kcal100
        protein100 = record.protein100
        carbs100 = record.carbs100
        sugars100 = record.sugars100
        fat100 = record.fat100
        saturatedFat100 = record.saturatedFat100
        fiber100 = record.fiber100
        salt100 = record.salt100
        imageURL = record.imageURL
        isVerified = record.isVerified
        fetchedAt = record.fetchedAt
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
