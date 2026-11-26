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

    /// What reading a photo of the nutrition table gave (TASKS 2.8).
    enum LabelNote: Equatable {
        /// Read: the user checks the values before saving.
        case read
        /// Read, but a value was left out or the energy does not fit the macros.
        case check
        /// No nutrition table on the photo that could be read.
        case nothing
    }

    private(set) var labelNote: LabelNote?
    private(set) var isReadingLabel = false

    private let diary: FoodDiary

    init(diary: FoodDiary, gtin: String?) {
        self.diary = diary
        self.gtin = gtin ?? ""
    }

    private var draft: OwnProductDraft {
        OwnProductDraft(
            name: name, brand: brand, gtin: gtin, isMillilitre: isMillilitre, kcal: kcal,
            protein: protein, carbs: carbs, fat: fat, servingSize: servingSize
        )
    }

    /// The checks and rounding of FitlingCore, the same as on the web.
    private var fields: OwnProductFields? {
        draft.validated()
    }

    /// A photo of the nutrition table, read by Vision on this iPhone away from the main actor.
    func readLabel(_ photo: Data) async {
        isReadingLabel = true
        let label = await Task.detached(priority: .userInitiated) { LabelReader.read(photo) }.value
        isReadingLabel = false
        useLabel(label)
    }

    /// What was read fills the fields that are still empty; what the user typed stays.
    func useLabel(_ label: NutritionLabel?) {
        guard let label, label.kcal != nil || label.protein != nil || label.carbs != nil || label.fat != nil else {
            labelNote = .nothing
            return
        }
        let filled = label.filling(draft)
        kcal = filled.kcal
        protein = filled.protein
        carbs = filled.carbs
        fat = filled.fat
        servingSize = filled.servingSize
        isMillilitre = filled.isMillilitre
        labelNote = label.needsCheck ? .check : .read
    }

    /// The same limits as the `check` rules on `products`.
    var canSave: Bool {
        fields != nil
    }

    func save() -> Product? {
        guard let fields else { return nil }
        // Stored under the user's own language; other languages fall back to it (`LocalizedText`).
        let language = Locale.preferredLanguages.first.map { String($0.prefix { $0 != "-" && $0 != "_" }) } ?? "nl"
        let product = Product(
            id: UUID(), ownerID: diary.userID, source: "user", name: LocalizedText([language: fields.name]),
            quantityUnit: fields.quantityUnit, updatedAt: diary.now()
        )
        product.brand = fields.brand
        product.gtin = fields.gtin
        product.searchName = fields.searchName
        product.servingSize = fields.servingSize
        product.kcal100 = fields.kcal100
        product.protein100 = fields.protein100
        product.carbs100 = fields.carbs100
        product.fat100 = fields.fat100
        diary.context.insert(product)
        try? diary.context.save()
        return product
    }
}
