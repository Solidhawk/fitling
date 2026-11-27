#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The rules for logging food that the app and the web share (D-24): how a search term is matched, which products
/// count as recent, and what an entry stores.
public enum FoodLog {
    /// How many products "recent" shows (ARCHITECTURE: the last 20 different products).
    public static let recentLimit = 20
    /// The database keeps at most this many characters of a name.
    public static let nameLimit = 200

    /// Lower case, without accents and without white space around it: the form `search_name` is stored in.
    public static func searchKey(_ text: String) -> String {
        text.folded.trimmingWhitespace()
    }

    /// The products of the newest entries first, each once. The caller keeps the first `recentLimit` it still has.
    public static func recentProductIDs(_ logged: [(productID: UUID, updatedAt: Date)]) -> [UUID] {
        var seen = Set<UUID>()
        return logged.sorted { $0.updatedAt > $1.updatedAt }.compactMap { entry in
            seen.insert(entry.productID).inserted ? entry.productID : nil
        }
    }

    /// The name an entry keeps: what the product was called when it was logged, at most 200 characters as the database
    /// counts them.
    public static func storedName(_ name: String) -> String {
        name.limited(toScalars: nameLimit)
    }

    /// The amount an entry keeps, to one decimal as the database stores it.
    public static func storedQuantity(_ quantity: Double) -> Double {
        (quantity * 10).rounded() / 10
    }
}

/// How much of one product: grams or millilitres, or servings when the product has a serving size (PortionView).
public struct Portion: Sendable, Equatable {
    /// The units this product can be logged in, the serving first.
    public let units: [QuantityUnit]
    public let defaultUnit: QuantityUnit
    public let defaultQuantity: Double

    public init(quantityUnit: String, servingSize: Double?) {
        let base: QuantityUnit = quantityUnit == "ml" ? .millilitre : .gram
        let hasServing = (servingSize ?? 0) > 0
        units = hasServing ? [.serving, base] : [base]
        defaultUnit = hasServing ? .serving : base
        defaultQuantity = hasServing ? 1 : 100
    }

    /// What this portion adds to the day, or nil while the amount is missing or the entry is outside what
    /// `food_entries` accepts: a row the database refuses would stay unsent on the iPhone for good.
    public static func preview(per100: NutrientsPer100, quantity: Double?, unit: QuantityUnit, servingSize: Double?) -> Nutrients? {
        guard let quantity, FoodLog.storedQuantity(quantity) > 0, quantity <= Limits.foodQuantity.upperBound,
              let nutrients = FoodMath.nutrients(per100: per100, quantity: quantity, unit: unit, servingSize: servingSize),
              nutrients.kcal <= Limits.entryKcal,
              (nutrients.proteinG ?? 0) <= Limits.entryProteinG,
              (nutrients.carbsG ?? 0) <= Limits.entryCarbsG,
              (nutrients.fatG ?? 0) <= Limits.entryFatG
        else { return nil }
        return nutrients
    }

    /// A product without kcal can be logged once the kcal on the package is within what the database accepts.
    public static func canSave(preview: Nutrients?, needsKcal: Bool, kcalOnPackage: Double?) -> Bool {
        guard preview != nil else { return false }
        if needsKcal {
            return kcalOnPackage.map { Limits.kcalPer100.contains($0) } ?? false
        }
        return true
    }
}

/// A product the user types in from the package (AddProductView), checked against the `check` rules on `products`.
public struct OwnProductDraft: Sendable, Equatable {
    public var name: String
    public var brand: String
    /// Empty for no barcode; a typed code must be a valid one.
    public var gtin: String
    public var isMillilitre: Bool
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var servingSize: Double?

    public init(
        name: String = "", brand: String = "", gtin: String = "", isMillilitre: Bool = false, kcal: Double? = nil,
        protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, servingSize: Double? = nil
    ) {
        self.name = name
        self.brand = brand
        self.gtin = gtin
        self.isMillilitre = isMillilitre
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
    }

    /// What is stored, rounded as the database keeps it; nil while the product cannot be saved.
    public func validated() -> OwnProductFields? {
        let trimmedName = name.trimmingWhitespace()
        guard !trimmedName.isEmpty, trimmedName.count <= FoodLog.nameLimit, let kcal, Limits.kcalPer100.contains(kcal) else { return nil }
        let code = gtin.trimmingSpaces()
        let storedGtin: String?
        if code.isEmpty {
            storedGtin = nil
        } else if let normalized = Barcode.normalized(code) {
            storedGtin = normalized
        } else {
            return nil
        }
        guard [protein, carbs, fat].compactMap({ $0 }).allSatisfy({ (0...100).contains($0) }) else { return nil }
        func hundredths(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        // `numeric(7,2) check (serving_size > 0)`: checked as it is stored, so 0,004 does not become 0.
        if let servingSize, !(hundredths(servingSize) > 0 && hundredths(servingSize) <= 99_999.99) { return nil }
        let brandText = brand.trimmingWhitespace()
        return OwnProductFields(
            name: trimmedName,
            brand: brandText.isEmpty ? nil : brandText,
            gtin: storedGtin,
            quantityUnit: isMillilitre ? "ml" : "g",
            servingSize: servingSize.map(hundredths),
            kcal100: (kcal * 10).rounded() / 10,
            protein100: protein.map(hundredths),
            carbs100: carbs.map(hundredths),
            fat100: fat.map(hundredths),
            searchName: FoodLog.searchKey([trimmedName, brandText].filter { !$0.isEmpty }.joined(separator: " "))
        )
    }
}

/// The columns of a product the user typed in, as they go into `products`.
public struct OwnProductFields: Sendable, Equatable, Codable {
    public let name: String
    public let brand: String?
    public let gtin: String?
    public let quantityUnit: String
    public let servingSize: Double?
    public let kcal100: Double
    public let protein100: Double?
    public let carbs100: Double?
    public let fat100: Double?
    public let searchName: String
}
