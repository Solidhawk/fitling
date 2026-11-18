import Foundation

// Raw values are the exact `check` values of `food_entries.quantity_unit`.
public enum QuantityUnit: String, Sendable, CaseIterable, Codable {
    case gram = "g"
    case millilitre = "ml"
    case serving
}

/// What a product says per 100 g or 100 ml. Nil means the source did not give the value.
public struct NutrientsPer100: Sendable, Equatable {
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?

    public init(kcal: Double?, proteinG: Double?, carbsG: Double?, fatG: Double?) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// What one log entry adds to the day. Energy is always known; a macro can be unknown.
public struct Nutrients: Sendable, Equatable {
    public var kcal: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?

    public init(kcal: Double, proteinG: Double?, carbsG: Double?, fatG: Double?) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

public struct DayTotals: Sendable, Equatable {
    public var kcal = 0.0
    public var proteinG = 0.0
    public var carbsG = 0.0
    public var fatG = 0.0
    public var entryCount = 0
    /// How many entries had no value for the macro. They count as 0 above, and the day
    /// overview says so instead of pretending the total is complete.
    public var unknownProtein = 0
    public var unknownCarbs = 0
    public var unknownFat = 0

    public init() {}
}

public enum FoodMath {
    public static let kilojoulesPerKcal = 4.184
    /// A label is suspect when the macros give more than this share more or less energy...
    public static let inconsistentShare = 0.25
    /// ...and the difference is also more than this many kcal, so tiny numbers do not trip it.
    public static let inconsistentKcal = 30.0

    /// The grams or millilitres that `quantity` stands for. Nil for servings of a product
    /// without a serving size, and for a quantity that is not positive.
    public static func amount(quantity: Double, unit: QuantityUnit, servingSize: Double?) -> Double? {
        nil
    }

    /// What `quantity` of a product adds to the day, rounded to one decimal as the database
    /// stores it. Nil when the product has no kcal or the amount cannot be worked out.
    public static func nutrients(per100: NutrientsPer100, quantity: Double, unit: QuantityUnit, servingSize: Double?) -> Nutrients? {
        nil
    }

    public static func kcal(fromKilojoules kilojoules: Double) -> Double {
        0
    }

    /// False when the energy on the label does not fit the macros (4 kcal per gram of protein
    /// and carbohydrate, 9 per gram of fat).
    public static func isConsistent(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) -> Bool {
        false
    }

    public static func totals(_ entries: [Nutrients]) -> DayTotals {
        DayTotals()
    }
}
