import Testing
@testable import FitlingCore

/// What the camera reads on the nutrition table of a package (TASKS 2.8): the values per 100 g or 100 ml, in the
/// languages of the shops the app is for.
@Suite struct NutritionLabelTests {
    @Test func aDutchTableWithAPortionColumnGivesThePer100Values() {
        let label = NutritionLabel.read([
            "Voedingswaarde per 100 g per portie (30 g)",
            "Energie 1569 kJ / 373 kcal 471 kJ / 112 kcal",
            "Vetten 7,0 g 2,1 g",
            "waarvan verzadigde vetzuren 1,3 g 0,4 g",
            "Koolhydraten 62 g 19 g",
            "waarvan suikers 21 g 6,3 g",
            "Voedingsvezel 7,5 g 2,3 g",
            "Eiwitten 9,2 g 2,8 g",
            "Zout 0,48 g 0,14 g",
        ])
        #expect(label.kcal == 373)
        #expect(label.fat == 7)
        #expect(label.saturatedFat == 1.3)
        #expect(label.carbs == 62)
        #expect(label.sugars == 21)
        #expect(label.fiber == 7.5)
        #expect(label.protein == 9.2)
        #expect(label.salt == 0.48)
        #expect(label.isMillilitre == false)
        #expect(label.servingSize == 30)
        #expect(label.needsCheck == false)
    }

    @Test func anEnglishLabelReadsTheSame() {
        let label = NutritionLabel.read([
            "Typical values Per 100g",
            "Energy 1046kJ/250kcal",
            "Fat 9.0g",
            "of which saturates 3.2g",
            "Carbohydrate 32g",
            "of which sugars 2.1g",
            "Fibre 2.5g",
            "Protein 8.3g",
            "Salt 1.1g",
        ])
        #expect(label.kcal == 250)
        #expect(label.fat == 9)
        #expect(label.saturatedFat == 3.2)
        #expect(label.carbs == 32)
        #expect(label.sugars == 2.1)
        #expect(label.fiber == 2.5)
        #expect(label.protein == 8.3)
        #expect(label.salt == 1.1)
    }

    @Test func aGermanLabelReadsTheSame() {
        let label = NutritionLabel.read([
            "Nährwerte pro 100 g",
            "Brennwert 1554 kJ / 371 kcal",
            "Fett 12 g",
            "davon gesättigte Fettsäuren 1,2 g",
            "Kohlenhydrate 55 g",
            "davon Zucker 20 g",
            "Ballaststoffe 4,5 g",
            "Eiweiß 7,0 g",
            "Salz 0,4 g",
        ])
        #expect(label.kcal == 371)
        #expect(label.fat == 12)
        #expect(label.saturatedFat == 1.2)
        #expect(label.carbs == 55)
        #expect(label.sugars == 20)
        #expect(label.fiber == 4.5)
        #expect(label.protein == 7)
        #expect(label.salt == 0.4)
    }

    @Test func energyOnTwoRowsAndOnlyKilojoulesAreRead() {
        let twoRows = NutritionLabel.read(["Energie (kJ) 1569", "Energie (kcal) 373", "Vet 7 g"])
        #expect(twoRows.kcal == 373)
        let valueOnItsOwnRow = NutritionLabel.read(["Energie 1569 kJ", "373 kcal", "Vet 7 g"])
        #expect(valueOnItsOwnRow.kcal == 373)
        // 1569 / 4.184 = 375.0
        let kilojoulesOnly = NutritionLabel.read(["Energie 1569 kJ", "Vet 7 g"])
        #expect(kilojoulesOnly.kcal == 375)
    }

    @Test func lessThanCountsAsItsBoundAndTracesAreRead() {
        let label = NutritionLabel.read(["Vet <0,5 g", "Zout < 0,01 g", "Eiwitten 0 g"])
        #expect(label.fat == 0.5)
        #expect(label.salt == 0.01)
        #expect(label.protein == 0)
    }

    @Test func drinksArePer100Millilitres() {
        let label = NutritionLabel.read(["Voedingswaarde per 100 ml", "Energie 180 kJ / 43 kcal", "Koolhydraten 10,6 g"])
        #expect(label.isMillilitre)
        #expect(label.kcal == 43)
        #expect(label.carbs == 10.6)
    }

    @Test func impossibleValuesAreLeftOutAndAWrongEnergyIsFlagged() {
        // Read wrong: 70 g of fat in 100 g is possible, 700 g is not; and 4·9 + 4·62 + 9·7 = 347 is far from 900.
        let label = NutritionLabel.read(["Energie 900 kcal", "Vet 700 g", "Koolhydraten 62 g", "Eiwitten 9 g"])
        #expect(label.fat == nil)
        #expect(label.kcal == 900)
        let wrong = NutritionLabel.read(["Energie 900 kcal", "Vet 7 g", "Koolhydraten 62 g", "Eiwitten 9 g"])
        #expect(wrong.needsCheck)
    }

    @Test func rowsComeFromPiecesSideBySide() {
        // Vision gives the name and the values of a row as separate pieces, a little apart in height.
        let rows = NutritionLabel.rows([
            .init(text: "1569 kJ / 373 kcal", x: 0.55, y: 0.212, height: 0.03),
            .init(text: "Vetten", x: 0.05, y: 0.30, height: 0.03),
            .init(text: "Energie", x: 0.05, y: 0.20, height: 0.03),
            .init(text: "7,0 g", x: 0.55, y: 0.305, height: 0.03),
        ])
        #expect(rows == ["Energie 1569 kJ / 373 kcal", "Vetten 7,0 g"])
    }

    @Test func whatWasReadFillsOnlyTheEmptyFieldsOfTheForm() {
        let label = NutritionLabel.read(["Energie 1569 kJ / 373 kcal", "Vetten 7,0 g", "Koolhydraten 62 g", "Eiwitten 9,2 g"])
        let draft = label.filling(OwnProductDraft(name: "Muesli", protein: 10))
        #expect(draft.name == "Muesli")
        #expect(draft.kcal == 373)
        #expect(draft.fat == 7)
        #expect(draft.carbs == 62)
        // Typed by the user before the photo: it stays.
        #expect(draft.protein == 10)
    }
}
