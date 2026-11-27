#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The rules for Vandaag and logging (web phase 2), the same as FoodDiary, PortionViewModel and AddProductViewModel
// use on iOS.

struct TextRequest: Decodable {
    let text: String
}

struct SearchKeyAnswer: Encodable {
    let key: String
    /// The key as a regular expression for `imatch` on `search_name`.
    let pattern: String
}

func searchKey(_ request: TextRequest) -> SearchKeyAnswer {
    let key = FoodLog.searchKey(request.text)
    return SearchKeyAnswer(key: key, pattern: FoodLog.searchPattern(key))
}

struct BarcodeAnswer: Encodable {
    /// The key a product is stored under, or nil for a misread.
    let gtin: String?
}

func barcode(_ request: TextRequest) -> BarcodeAnswer {
    BarcodeAnswer(gtin: Barcode.normalized(request.text))
}

struct LoggedInput: Decodable {
    let productID: UUID
    /// Milliseconds since 1970, as JavaScript's Date.getTime().
    let updatedAtMs: Double
}

struct RecentRequest: Decodable {
    let logged: [LoggedInput]
}

struct RecentAnswer: Encodable {
    /// In lower case, as Postgres writes a uuid.
    let ids: [String]
    let limit: Int
}

func recentProducts(_ request: RecentRequest) -> RecentAnswer {
    let logged = request.logged.map { (productID: $0.productID, updatedAt: Date(timeIntervalSince1970: $0.updatedAtMs / 1000)) }
    return RecentAnswer(ids: FoodLog.recentProductIDs(logged).map { $0.uuidString.lowercased() }, limit: FoodLog.recentLimit)
}

/// Per 100 g or 100 ml; nil is unknown.
struct Per100Input: Decodable {
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?

    var nutrients: NutrientsPer100 {
        NutrientsPer100(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

struct NutrientsOutput: Encodable {
    let kcal: Double
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?

    init(_ nutrients: Nutrients) {
        kcal = nutrients.kcal
        proteinG = nutrients.proteinG
        carbsG = nutrients.carbsG
        fatG = nutrients.fatG
    }
}

struct PortionRequest: Decodable {
    let quantityUnit: String
    let servingSize: Double?
    let per100: Per100Input
    /// Missing: the portion the product starts at.
    let quantity: Double?
    let unit: QuantityUnit?
    let kcalOnPackage: Double?
}

struct PortionAnswer: Encodable {
    let units: [QuantityUnit]
    let defaultUnit: QuantityUnit
    let defaultQuantity: Double
    let preview: NutrientsOutput?
    let needsKcal: Bool
    let canSave: Bool
    /// Why the typed amount cannot be logged; none while the field is empty (Portion.problem).
    let problem: Portion.Problem?
}

func portion(_ request: PortionRequest) -> PortionAnswer {
    let portion = Portion(quantityUnit: request.quantityUnit, servingSize: request.servingSize)
    let needsKcal = request.per100.kcal == nil
    var per100 = request.per100.nutrients
    if needsKcal { per100.kcal = request.kcalOnPackage }
    let preview = Portion.preview(
        per100: per100, quantity: request.quantity ?? portion.defaultQuantity, unit: request.unit ?? portion.defaultUnit,
        servingSize: request.servingSize
    )
    return PortionAnswer(
        units: portion.units, defaultUnit: portion.defaultUnit, defaultQuantity: portion.defaultQuantity,
        preview: preview.map(NutrientsOutput.init), needsKcal: needsKcal,
        canSave: Portion.canSave(preview: preview, needsKcal: needsKcal, kcalOnPackage: request.kcalOnPackage),
        problem: Portion.problem(
            per100: per100, quantity: request.quantity, unit: request.unit ?? portion.defaultUnit, servingSize: request.servingSize
        )
    )
}

struct LogEntryRequest: Decodable {
    let name: String
    let quantity: Double
    let unit: QuantityUnit
    let servingSize: Double?
    let per100: Per100Input
}

struct LogEntryAnswer: Encodable {
    let name: String
    let quantity: Double
    let nutrients: NutrientsOutput
}

/// What an entry stores, as FoodDiary.log: nil when the product has no kcal or the amount cannot be worked out.
func logEntry(_ request: LogEntryRequest) -> LogEntryAnswer? {
    guard let nutrients = FoodMath.nutrients(
        per100: request.per100.nutrients, quantity: request.quantity, unit: request.unit, servingSize: request.servingSize
    ) else { return nil }
    return LogEntryAnswer(name: FoodLog.storedName(request.name), quantity: FoodLog.storedQuantity(request.quantity), nutrients: NutrientsOutput(nutrients))
}

struct OwnProductRequest: Decodable {
    let name: String
    let brand: String
    let gtin: String
    let isMillilitre: Bool
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let servingSize: Double?
}

struct OwnProductAnswer: Encodable {
    /// Nil while the product cannot be saved.
    let fields: OwnProductFields?
}

func ownProduct(_ request: OwnProductRequest) -> OwnProductAnswer {
    let draft = OwnProductDraft(
        name: request.name, brand: request.brand, gtin: request.gtin, isMillilitre: request.isMillilitre, kcal: request.kcal,
        protein: request.protein, carbs: request.carbs, fat: request.fat, servingSize: request.servingSize
    )
    return OwnProductAnswer(fields: draft.validated())
}

struct DayTotalsRequest: Decodable {
    let entries: [Per100Input]
}

struct DayTotalsAnswer: Encodable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let entryCount: Int
    let unknownProtein: Int
    let unknownCarbs: Int
    let unknownFat: Int
}

/// The day's totals of what was logged; `entries` carry what each entry added (kcal is always known).
func dayTotals(_ request: DayTotalsRequest) -> DayTotalsAnswer {
    let totals = FoodMath.totals(request.entries.map { Nutrients(kcal: $0.kcal ?? 0, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG) })
    return DayTotalsAnswer(
        kcal: totals.kcal, proteinG: totals.proteinG, carbsG: totals.carbsG, fatG: totals.fatG, entryCount: totals.entryCount,
        unknownProtein: totals.unknownProtein, unknownCarbs: totals.unknownCarbs, unknownFat: totals.unknownFat
    )
}

struct LocalizedTextRequest: Decodable {
    /// As jsonb stores it: {"nl": "Brood", "en": "Bread"}.
    let values: [String: String]
    /// The browser's languages, most wanted first.
    let languages: [String]
}

struct LocalizedTextAnswer: Encodable {
    let text: String
}

/// A name from the database in the user's language, with the fallbacks of LocalizedText.
func localizedText(_ request: LocalizedTextRequest) -> LocalizedTextAnswer {
    LocalizedTextAnswer(text: LocalizedText(request.values).text(preferring: request.languages))
}
