import Foundation
import Observation
import SwiftData
import FitlingCore

/// A product the user types in from the package: private to them, synced like their other data.
@Observable
@MainActor
final class AddProductViewModel {
    var name = ""
    var brand = ""
    var gtin: String
    var isMillilitre = false
    var servingSize: Double?
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    private let diary: FoodDiary

    init(diary: FoodDiary, gtin: String?) {
        self.diary = diary
        self.gtin = gtin ?? ""
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The barcode as stored, or nil when the field is empty; a typed code must be valid.
    private var normalizedGtin: String?? {
        let code = gtin.trimmingCharacters(in: .whitespaces)
        if code.isEmpty { return .some(nil) }
        return Barcode.normalized(code).map { .some($0) }
    }

    /// The same limits as the `check` rules on `products`.
    var canSave: Bool {
        guard !trimmedName.isEmpty, trimmedName.count <= 200, normalizedGtin != nil,
              let kcal, Limits.kcalPer100.contains(kcal) else { return false }
        let grams = [protein, carbs, fat].compactMap { $0 }
        guard grams.allSatisfy({ (0...100).contains($0) }) else { return false }
        if let servingSize { return servingSize > 0 && servingSize < 100_000 }
        return true
    }

    func save() -> Product? {
        return nil
        guard canSave, let kcal, let gtinValue = normalizedGtin else { return nil }
        // Stored under the user's own language; other languages fall back to it (`LocalizedText`).
        let language = Locale.preferredLanguages.first.map { String($0.prefix { $0 != "-" && $0 != "_" }) } ?? "nl"
        let product = Product(
            id: UUID(), ownerID: diary.userID, source: "user", name: LocalizedText([language: trimmedName]),
            quantityUnit: isMillilitre ? "ml" : "g", updatedAt: diary.now()
        )
        let brandText = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        product.brand = brandText.isEmpty ? nil : brandText
        product.gtin = gtinValue
        product.searchName = FoodDiary.searchKey([trimmedName, brandText].filter { !$0.isEmpty }.joined(separator: " "))
        product.servingSize = servingSize.map { ($0 * 100).rounded() / 100 }
        product.kcal100 = (kcal * 10).rounded() / 10
        product.protein100 = protein.map { ($0 * 100).rounded() / 100 }
        product.carbs100 = carbs.map { ($0 * 100).rounded() / 100 }
        product.fat100 = fat.map { ($0 * 100).rounded() / 100 }
        diary.context.insert(product)
        try? diary.context.save()
        return product
    }
}
