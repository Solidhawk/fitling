import Foundation
import Testing
@testable import FitlingCore

/// The rules for logging food that the app and the web share (web phase 2, D-24).
@Suite struct FoodLogRulesTests {
    @Test func searchKeyFoldsCaseAndAccents() {
        #expect(FoodLog.searchKey("  Crème Brûlée\n") == "creme brulee")
        #expect(FoodLog.searchKey("   ") == "")
    }

    @Test func recentShowsEachProductOnceNewestFirst() {
        let a = UUID()
        let b = UUID()
        let logged = [
            (productID: a, updatedAt: Date(timeIntervalSince1970: 1)),
            (productID: b, updatedAt: Date(timeIntervalSince1970: 2)),
            (productID: a, updatedAt: Date(timeIntervalSince1970: 3)),
        ]
        #expect(FoodLog.recentProductIDs(logged) == [a, b])
    }

    /// The server searches with a regular expression: every character of the term counts as itself, a "*" too
    /// (diary.test.ts, aSearchTermIsTakenLiterally, runs the same search against PostgREST).
    @Test func aSearchPatternTakesEveryCharacterLiterally() {
        #expect(FoodLog.searchPattern("pindakaas") == "pindakaas")
        #expect(FoodLog.searchPattern("50% *x*. (a+b)") == #"50% \*x\*\. \(a\+b\)"#)
        #expect(FoodLog.searchPattern(#"^$|?{2} [c] \_"#) == #"\^\$\|\?\{2\} \[c\] \\_"#)
        // A keycap is one character of "*" and an enclosing mark (review of Fable 5.2): its "*" is escaped all the same.
        #expect(FoodLog.searchPattern(FoodLog.searchKey("*️⃣ ab")) == "\\*\u{20E3} ab")
    }

    @Test func anEntryKeepsAtMost200CharactersAndOneDecimal() {
        #expect(FoodLog.storedName(String(repeating: "a", count: 250)).count == 200)
        #expect(FoodLog.storedQuantity(123.45) == 123.5)
    }

    @Test func portionStartsAtOneServingOrHundred() {
        let serving = Portion(quantityUnit: "g", servingSize: 30)
        #expect(serving.units == [.serving, .gram])
        #expect(serving.defaultUnit == .serving)
        #expect(serving.defaultQuantity == 1)
        let drink = Portion(quantityUnit: "ml", servingSize: nil)
        #expect(drink.units == [.millilitre])
        #expect(drink.defaultUnit == .millilitre)
        #expect(drink.defaultQuantity == 100)
    }

    @Test func aPortionNeedsAPositiveAmountWithinTheLimit() {
        let per100 = NutrientsPer100(kcal: 250, proteinG: 10, carbsG: nil, fatG: 5)
        #expect(Portion.preview(per100: per100, quantity: 0, unit: .gram, servingSize: nil) == nil)
        #expect(Portion.preview(per100: per100, quantity: 10_001, unit: .gram, servingSize: nil) == nil)
        #expect(Portion.preview(per100: per100, quantity: nil, unit: .gram, servingSize: nil) == nil)
        #expect(Portion.preview(per100: per100, quantity: 40, unit: .gram, servingSize: nil) == Nutrients(kcal: 100, proteinG: 4, carbsG: nil, fatG: 2))
    }

    @Test func withoutKcalThePackageValueDecides() {
        let preview = Nutrients(kcal: 100, proteinG: nil, carbsG: nil, fatG: nil)
        #expect(!Portion.canSave(preview: nil, needsKcal: false, kcalOnPackage: nil))
        #expect(Portion.canSave(preview: preview, needsKcal: false, kcalOnPackage: nil))
        #expect(!Portion.canSave(preview: preview, needsKcal: true, kcalOnPackage: nil))
        #expect(!Portion.canSave(preview: preview, needsKcal: true, kcalOnPackage: 950))
        #expect(Portion.canSave(preview: preview, needsKcal: true, kcalOnPackage: 250))
    }

    /// AddProductTests in the app: " Oma's appeltaart " from Bakkerij Jansen.
    func draft(gtin: String = "8712100849084") -> OwnProductDraft {
        OwnProductDraft(name: " Oma's appeltaart ", brand: "Bakkerij Jansen", gtin: gtin, kcal: 280.44, protein: 3.2, carbs: 38, servingSize: 120)
    }

    @Test func ownProductRoundsAsTheDatabaseStores() throws {
        let fields = try #require(draft().validated())
        #expect(fields.name == "Oma's appeltaart")
        #expect(fields.brand == "Bakkerij Jansen")
        #expect(fields.gtin == "8712100849084")
        #expect(fields.quantityUnit == "g")
        #expect(fields.kcal100 == 280.4)
        #expect(fields.fat100 == nil)
        #expect(fields.servingSize == 120)
        #expect(fields.searchName == "oma's appeltaart bakkerij jansen")
    }

    @Test func ownProductUsesTheDatabaseLimits() {
        #expect(draft(gtin: "").validated()?.gtin == .some(nil))
        #expect(draft(gtin: "8712100849085").validated() == nil)
        #expect(draft(gtin: "036000291452").validated()?.gtin == "0036000291452")
        var tooMuch = draft()
        tooMuch.kcal = 950
        #expect(tooMuch.validated() == nil)
        var tooMuchProtein = draft()
        tooMuchProtein.protein = 120
        #expect(tooMuchProtein.validated() == nil)
        var noName = draft()
        noName.name = "  "
        #expect(noName.validated() == nil)
    }
}
