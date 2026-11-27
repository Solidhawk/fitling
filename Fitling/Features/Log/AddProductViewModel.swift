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
        /// The photo could not be opened.
        case unreadable
    }

    private(set) var labelNote: LabelNote?
    private(set) var isReadingLabel = false
    /// What the last photo put in the form. A next photo may replace those values while the user leaves them as they
    /// are; what the user typed or changed stays.
    private var fromLabel = NutritionLabel()

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

    /// A photo of the nutrition table, opened and read by Vision on this iPhone away from the main actor. `load` gives
    /// the photo, from the library or the camera, or nil when it could not be had.
    func readLabel(_ load: @escaping @Sendable () async -> Data?) async {
        isReadingLabel = true
        defer { isReadingLabel = false }
        let label = await Task.detached(priority: .userInitiated) { () async -> NutritionLabel? in
            guard let photo = await load() else { return nil }
            return LabelReader.read(photo)
        }.value
        guard let label else {
            labelNote = .unreadable
            return
        }
        useLabel(label)
    }

    /// What was read fills the fields that are still empty, and those the last photo filled that the user left as they
    /// were; what the user typed stays.
    func useLabel(_ label: NutritionLabel) {
        guard label.kcal != nil || label.protein != nil || label.carbs != nil || label.fat != nil else {
            labelNote = .nothing
            return
        }
        // Open again where the last photo put the value and the new one has a value of its own: a photo that misses a
        // value does not take away what the one before read.
        func open(_ value: Double?, _ last: Double?, _ read: Double?) -> Double? { value == last && read != nil ? nil : value }
        var draft = self.draft
        draft.kcal = open(kcal, fromLabel.kcal, label.kcal)
        draft.protein = open(protein, fromLabel.protein, label.protein)
        draft.carbs = open(carbs, fromLabel.carbs, label.carbs)
        draft.fat = open(fat, fromLabel.fat, label.fat)
        draft.servingSize = open(servingSize, fromLabel.servingSize, label.servingSize)
        if isMillilitre == fromLabel.isMillilitre { draft.isMillilitre = false }
        let filled = label.filling(draft)
        // Remembered as what the photo put there; a field the user had typed is not the photo's.
        func photos(_ opened: Double?, _ now: Double?, _ last: Double?) -> Double? { opened == nil || now == last ? now : nil }
        var fromPhoto = NutritionLabel()
        fromPhoto.kcal = photos(draft.kcal, filled.kcal, fromLabel.kcal)
        fromPhoto.protein = photos(draft.protein, filled.protein, fromLabel.protein)
        fromPhoto.carbs = photos(draft.carbs, filled.carbs, fromLabel.carbs)
        fromPhoto.fat = photos(draft.fat, filled.fat, fromLabel.fat)
        fromPhoto.servingSize = photos(draft.servingSize, filled.servingSize, fromLabel.servingSize)
        fromPhoto.isMillilitre = filled.isMillilitre
        fromLabel = fromPhoto
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
