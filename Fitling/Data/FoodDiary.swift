import Foundation
import SwiftData
import FitlingCore

/// What the user ate and drank, read and written on the main context. Every write marks the
/// row for the next sync; nothing here talks to the network.
@MainActor
struct FoodDiary {
    let context: ModelContext
    let userID: UUID
    var now: () -> Date = Date.init

    /// How many products "recent" shows (ARCHITECTURE: the last 20 different products).
    static let recentLimit = 20

    func entries(on day: Day) -> [FoodEntry] {
        let dayString = day.isoString
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.consumedOn == dayString && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func waterMl(on day: Day) -> Int {
        let dayString = day.isoString
        let descriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate<WaterEntry> { $0.consumedOn == dayString && $0.deletedAt == nil }
        )
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.amountMl }
    }

    /// One glass at a time, so two devices that log water offline add up instead of colliding.
    func addWater(_ amountMl: Int, on day: Day) {
        context.insert(WaterEntry(id: UUID(), userID: userID, consumedOn: day, amountMl: amountMl, updatedAt: now()))
        try? context.save()
    }

    /// Stores what `quantity` of the product adds to the day, as it is now: changing the product
    /// later does not change this entry. Nil when the product has no kcal or the amount cannot be
    /// worked out (servings of a product without a serving size).
    @discardableResult
    func log(_ product: Product, quantity: Double, unit: QuantityUnit, meal: MealSlot, on day: Day, languages: [String]) -> FoodEntry? {
        let per100 = NutrientsPer100(kcal: product.kcal100, proteinG: product.protein100, carbsG: product.carbs100, fatG: product.fat100)
        guard let nutrients = FoodMath.nutrients(per100: per100, quantity: quantity, unit: unit, servingSize: product.servingSize) else {
            return nil
        }
        let name = product.name.text(preferring: languages)
        let entry = FoodEntry(
            id: UUID(), userID: userID, consumedOn: day, meal: meal, name: String(name.prefix(200)),
            quantity: (quantity * 10).rounded() / 10, quantityUnit: unit.rawValue, kcal: nutrients.kcal, updatedAt: now()
        )
        entry.productID = product.id
        entry.proteinG = nutrients.proteinG
        entry.carbsG = nutrients.carbsG
        entry.fatG = nutrients.fatG
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// A deletion is a marker until the server has it; then the sync removes the row.
    func delete(_ entry: FoodEntry) {
        entry.deletedAt = now()
        entry.updatedAt = now()
        entry.needsPush = true
        try? context.save()
    }

    /// The last different products the user logged, most recent first.
    func recentProducts() -> [Product] {
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.deletedAt == nil && $0.productID != nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        var seen = Set<UUID>()
        var products: [Product] = []
        for entry in (try? context.fetch(descriptor)) ?? [] {
            guard let id = entry.productID, seen.insert(id).inserted, let product = product(id) else { continue }
            products.append(product)
            if products.count == Self.recentLimit { break }
        }
        return products
    }

    func favoriteProducts() -> [Product] {
        let descriptor = FetchDescriptor<FavoriteProduct>(predicate: #Predicate<FavoriteProduct> { $0.deletedAt == nil })
        var seen = Set<UUID>()
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { seen.insert($0.productID).inserted }
            .compactMap { product($0.productID) }
    }

    func isFavorite(_ product: Product) -> Bool {
        let id = product.id
        let descriptor = FetchDescriptor<FavoriteProduct>(predicate: #Predicate<FavoriteProduct> { $0.productID == id && $0.deletedAt == nil })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func setFavorite(_ product: Product, _ favorite: Bool) {
        let id = product.id
        let descriptor = FetchDescriptor<FavoriteProduct>(predicate: #Predicate<FavoriteProduct> { $0.productID == id && $0.deletedAt == nil })
        let existing = (try? context.fetch(descriptor)) ?? []
        if favorite, existing.isEmpty {
            context.insert(FavoriteProduct(id: UUID(), userID: userID, productID: id, updatedAt: now()))
        } else if !favorite {
            for row in existing {
                row.deletedAt = now()
                row.updatedAt = now()
                row.needsPush = true
            }
        }
        try? context.save()
    }

    /// Products on this device whose name or brand contains the text, ignoring case and accents.
    func searchLocally(_ text: String) -> [Product] {
        let term = Self.searchKey(text)
        guard !term.isEmpty else { return [] }
        var descriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { $0.deletedAt == nil && $0.searchName.contains(term) }
        )
        descriptor.fetchLimit = 30
        return (try? context.fetch(descriptor)) ?? []
    }

    /// For a product the source gave no kcal for: the user's own copy with the kcal they read
    /// on the package. The shared row stays as it is (ARCHITECTURE §5.2).
    func ownCopy(of product: Product, kcal100: Double) -> Product {
        let copy = Product(id: UUID(), ownerID: userID, source: "user", name: product.name, quantityUnit: product.quantityUnit, updatedAt: now())
        copy.gtin = product.gtin
        copy.brand = product.brand
        copy.searchName = product.searchName
        copy.servingSize = product.servingSize
        copy.servingLabel = product.servingLabel
        copy.kcal100 = kcal100
        copy.protein100 = product.protein100
        copy.carbs100 = product.carbs100
        copy.sugars100 = product.sugars100
        copy.fat100 = product.fat100
        copy.saturatedFat100 = product.saturatedFat100
        copy.fiber100 = product.fiber100
        copy.salt100 = product.salt100
        copy.imageURL = product.imageURL
        context.insert(copy)
        try? context.save()
        return copy
    }

    func product(_ id: UUID) -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Lower case without accents, the form `search_name` is stored in.
    static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
