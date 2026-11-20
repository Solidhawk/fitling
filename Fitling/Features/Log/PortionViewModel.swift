import Foundation
import Observation
import SwiftData
import FitlingCore

/// How much of one product: grams or millilitres, or servings when the product has a serving
/// size. A product without kcal first asks for the kcal on the package.
@Observable
@MainActor
final class PortionViewModel {
    private(set) var product: Product
    var quantity: Double?
    var unit: QuantityUnit
    /// Only used while the product has no kcal.
    var kcalOnPackage: Double?

    private let diary: FoodDiary
    private let meal: MealSlot
    private let day: Day
    private let languages: [String]

    init(product: Product, diary: FoodDiary, meal: MealSlot, day: Day, languages: [String] = Locale.preferredLanguages) {
        self.product = product
        self.diary = diary
        self.meal = meal
        self.day = day
        self.languages = languages
        let hasServing = (product.servingSize ?? 0) > 0
        unit = hasServing ? .serving : (product.quantityUnit == "ml" ? .millilitre : .gram)
        quantity = hasServing ? 1 : 100
    }

    var name: String {
        product.name.text(preferring: languages)
    }

    var needsKcal: Bool {
        product.kcal100 == nil
    }

    /// The units this product can be logged in.
    var units: [QuantityUnit] {
        let base: QuantityUnit = product.quantityUnit == "ml" ? .millilitre : .gram
        return (product.servingSize ?? 0) > 0 ? [.serving, base] : [base]
    }

    var isFavorite: Bool {
        diary.isFavorite(product)
    }

    func toggleFavorite() {
        diary.setFavorite(product, !isFavorite)
    }

    /// What this portion adds to the day, or nil while something is missing.
    var preview: Nutrients? {
        guard let quantity, quantity > 0, quantity <= Limits.foodQuantity.upperBound else { return nil }
        let per100 = NutrientsPer100(
            kcal: product.kcal100 ?? kcalOnPackage, proteinG: product.protein100, carbsG: product.carbs100, fatG: product.fat100
        )
        return FoodMath.nutrients(per100: per100, quantity: quantity, unit: unit, servingSize: product.servingSize)
    }

    var hasUnknownMacros: Bool {
        product.protein100 == nil || product.carbs100 == nil || product.fat100 == nil
    }

    var canSave: Bool {
        guard preview != nil else { return false }
        if needsKcal {
            return kcalOnPackage.map { Limits.kcalPer100.contains($0) } ?? false
        }
        return true
    }

    /// Stores the entry. A product without kcal becomes the user's own copy with the kcal they
    /// entered; the shared product stays as it is.
    @discardableResult
    func save() -> FoodEntry? {
        guard canSave, let quantity else { return nil }
        if needsKcal, let kcalOnPackage {
            product = diary.ownCopy(of: product, kcal100: kcalOnPackage)
        }
        return diary.log(product, quantity: quantity, unit: unit, meal: meal, on: day, languages: languages)
    }
}
