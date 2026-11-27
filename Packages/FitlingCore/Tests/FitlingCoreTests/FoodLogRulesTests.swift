import Foundation
import Testing
@testable import FitlingCore

/// The rules for logging food that the app and the web share (web phase 2, D-24).
@Suite struct FoodLogRulesTests {
    @Test func searchKeyFoldsCaseAndAccents() {
        #expect(FoodLog.searchKey("  Crème Brûlée\n") == "creme brulee")
        #expect(FoodLog.searchKey("   ") == "")
        // ß has no decomposition: it stays, as on the server (lookup-product and submit-product, NFD without marks).
        // A German product is found as it is written, "straße", not as "strasse".
        #expect(FoodLog.searchKey("Straße") == "straße")
        // Letters without a decomposition stay too, and a stroke is no accent.
        #expect(FoodLog.searchKey("Ærøskøbing Łódź") == "ærøskøbing łodz")
        #expect(FoodLog.searchKey("Йогурт") == "иогурт")
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
        // Postgres counts code points: a flag takes two of the 200, and a character is never cut in half.
        #expect(FoodLog.storedName(String(repeating: "🇳🇱", count: 150)) == String(repeating: "🇳🇱", count: 100))
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

    /// What the database refuses would stay unsent on the iPhone for good (S40): an amount that rounds to 0, and an
    /// entry beyond what `food_entries` accepts, such as a kilo of oil typed as ten.
    @Test func aPortionTheDatabaseWouldRefuseCannotBeLogged() {
        let oil = NutrientsPer100(kcal: 900, proteinG: 0, carbsG: 0, fatG: 100)
        #expect(Portion.preview(per100: oil, quantity: 0.04, unit: .gram, servingSize: nil) == nil)
        #expect(Portion.preview(per100: oil, quantity: 0.05, unit: .gram, servingSize: nil) != nil)
        // Chocolate: 3 700 g is 20 350 kcal, more than the 20 000 of one entry; 3 600 g is 19 800 kcal.
        let chocolate = NutrientsPer100(kcal: 550, proteinG: 7, carbsG: 60, fatG: 30)
        #expect(Portion.preview(per100: chocolate, quantity: 3700, unit: .gram, servingSize: nil) == nil)
        #expect(Portion.preview(per100: chocolate, quantity: 3600, unit: .gram, servingSize: nil) != nil)
        // Oil: 2 500 g is 2 500 g of fat, more than the 2 000 g of one entry.
        #expect(Portion.preview(per100: oil, quantity: 2500, unit: .gram, servingSize: nil) == nil)
        // 25 servings of 100 g of pure protein: 2 500 g, more than the 2 000 g of one entry.
        let powder = NutrientsPer100(kcal: 400, proteinG: 100, carbsG: 0, fatG: 0)
        #expect(Portion.preview(per100: powder, quantity: 25, unit: .serving, servingSize: 100) == nil)
        #expect(Portion.preview(per100: powder, quantity: 20, unit: .serving, servingSize: 100) != nil)
    }

    /// Save is off for a portion outside those limits; the line under the amount says why (review of Fable 5.2).
    @Test func aPortionSaysWhyItCannotBeLogged() {
        let chocolate = NutrientsPer100(kcal: 550, proteinG: 7, carbsG: 60, fatG: 30)
        func problem(_ quantity: Double?, _ unit: QuantityUnit = .gram) -> Portion.Problem? {
            Portion.problem(per100: chocolate, quantity: quantity, unit: unit, servingSize: 400)
        }
        #expect(problem(nil) == nil)
        #expect(problem(100) == nil)
        #expect(problem(0) == .tooLittle)
        #expect(problem(0.04) == .tooLittle)
        #expect(problem(-5) == .tooLittle)
        #expect(problem(.nan) == .tooLittle)
        #expect(problem(3700) == .tooMuch)
        #expect(problem(20_000) == .tooMuch)
        // Ten servings of 400 g: 22 000 kcal.
        #expect(problem(10, .serving) == .tooMuch)
        // Without kcal the field for the package explains it; no second line.
        let unknown = NutrientsPer100(kcal: nil, proteinG: 7, carbsG: 60, fatG: 30)
        #expect(Portion.problem(per100: unknown, quantity: 100, unit: .gram, servingSize: nil) == nil)
        // 9000 kcal typed from the package: the kcal field is wrong, not the 300 g (review of Fable 5.2).
        let mistyped = NutrientsPer100(kcal: 9000, proteinG: 7, carbsG: 60, fatG: 30)
        #expect(Portion.problem(per100: mistyped, quantity: 300, unit: .gram, servingSize: nil) == nil)
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

    /// `products.serving_size` keeps two decimals, above 0 and below 100 000: checked as it is stored.
    @Test func aServingSizeIsCheckedAsTheDatabaseStoresIt() {
        var tiny = draft()
        tiny.servingSize = 0.004
        #expect(tiny.validated() == nil)
        var large = draft()
        large.servingSize = 99_999.996
        #expect(large.validated() == nil)
        var largest = draft()
        largest.servingSize = 99_999.99
        #expect(largest.validated()?.servingSize == 99_999.99)
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
