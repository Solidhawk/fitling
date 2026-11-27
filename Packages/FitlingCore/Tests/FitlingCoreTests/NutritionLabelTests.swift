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

    // Review of Fable 5.2: labels as they are in the shops.

    @Test func bareEnergyNumbersFollowTheUnitsNamedBeforeThem() {
        #expect(NutritionLabel.read(["Energie kJ/kcal 1554/371"]).kcal == 371)
        #expect(NutritionLabel.read(["Energie kJ/kcal 180/43"]).kcal == 43)
        #expect(NutritionLabel.read(["Energie 1569 kJ", "kcal 373"]).kcal == 373)
        // A thousand separator before kJ: 1554 / 4.184 = 371.4.
        #expect(NutritionLabel.read(["Energie 1.554 kJ"]).kcal == 371.4)
    }

    @Test func aTiltedPhotoStillGivesItsRows() {
        // Three degrees: each row runs 0.05 down per width, more than half a line over the photo.
        let rows = NutritionLabel.rows([
            .init(text: "Energie", x: 0.05, y: 0.2025, height: 0.03, slope: 0.05),
            .init(text: "1569 kJ / 373 kcal", x: 0.55, y: 0.2275, height: 0.03, slope: 0.05),
            .init(text: "Vetten", x: 0.05, y: 0.3025, height: 0.03, slope: 0.05),
            .init(text: "7,0 g", x: 0.55, y: 0.3275, height: 0.03, slope: 0.05),
        ])
        #expect(rows == ["Energie 1569 kJ / 373 kcal", "Vetten 7,0 g"])
    }

    /// A sticker printed at an angle on a straight package: its slope does not tilt the table.
    @Test func aStampAtAnAngleDoesNotTiltAStraightTable() {
        let rows = NutritionLabel.rows([
            .init(text: "NIEUW", x: 0.8, y: 0.1, height: 0.05, slope: 0.35),
            .init(text: "Energie", x: 0.05, y: 0.20, height: 0.03),
            .init(text: "1569 kJ / 373 kcal", x: 0.55, y: 0.20, height: 0.03),
            .init(text: "Vetten", x: 0.05, y: 0.30, height: 0.03),
            .init(text: "7,0 g", x: 0.55, y: 0.30, height: 0.03),
        ])
        #expect(rows == ["NIEUW", "Energie 1569 kJ / 373 kcal", "Vetten 7,0 g"])
    }

    /// What Vision gave on the simulator for the table of FoodLogTests turned 5 degrees (CI run 45922631819): a tilted box
    /// for the longer pieces, with the slope of the photo, and an upright one, slope 0, for the short ones.
    @Test func aTiltedPhotoAsVisionReadsItGivesItsRows() {
        let rows = NutritionLabel.rows([
            .init(text: "Voedingswaarde", x: 0.2370, y: 0.1420, height: 0.0710, slope: 0.1309),
            .init(text: "per 100 g", x: 0.5905, y: 0.1938, height: 0.0680, slope: 0.0229),
            .init(text: "Energie", x: 0.1505, y: 0.2470, height: 0.0700, slope: 0),
            .init(text: "1569 kJ / 373 kcal", x: 0.6605, y: 0.3155, height: 0.0700, slope: 0.1343),
            .init(text: "Vetten", x: 0.1355, y: 0.3665, height: 0.0500, slope: 0.1304),
            .init(text: "7,0 g", x: 0.5330, y: 0.4267, height: 0.0670, slope: 0),
            .init(text: "Koolhydraten", x: 0.1895, y: 0.4975, height: 0.0790, slope: 0.1388),
            .init(text: "62 g", x: 0.5235, y: 0.5450, height: 0.0700, slope: 0),
            .init(text: "Eiwitten", x: 0.1345, y: 0.6115, height: 0.0490, slope: 0.1295),
            .init(text: "9,2 g", x: 0.5210, y: 0.6680, height: 0.0680, slope: 0),
            .init(text: "Zout", x: 0.0995, y: 0.7280, height: 0.0560, slope: 0),
            .init(text: "0,48 g", x: 0.5275, y: 0.7920, height: 0.0720, slope: 0),
        ])
        #expect(rows == [
            "Voedingswaarde per 100 g", "Energie 1569 kJ / 373 kcal", "Vetten 7,0 g", "Koolhydraten 62 g", "Eiwitten 9,2 g",
            "Zout 0,48 g",
        ])
        let label = NutritionLabel.read(rows)
        #expect(label.kcal == 373 && label.fat == 7 && label.carbs == 62 && label.protein == 9.2 && label.salt == 0.48)
    }

    /// A straight table with the heading above the values only and a note under the names (review of Fable 5.2): a
    /// slope that pairs each name with the value of the row above lines the pieces up in as few lines, and must not win.
    @Test func aHeadingAboveTheValuesDoesNotShiftTheRows() {
        let names = ["Energie", "Vetten", "waarvan verzadigd", "Koolhydraten", "waarvan suikers", "Eiwitten", "Zout"]
        let values = ["1569 kJ / 373 kcal", "7,0 g", "1,2 g", "62 g", "3,1 g", "9,2 g", "0,48 g"]
        var pieces = [NutritionLabel.Piece(text: "per 100 g", x: 0.7, y: 0.30, height: 0.02)]
        for (index, row) in zip(names, values).enumerated() {
            let y = 0.33 + 0.03 * Double(index)
            pieces.append(.init(text: row.0, x: 0.25, y: y, height: 0.02))
            pieces.append(.init(text: row.1, x: 0.7, y: y, height: 0.02))
        }
        pieces.append(.init(text: "* Referentie-inname", x: 0.25, y: 0.54, height: 0.02))
        #expect(NutritionLabel.rows(pieces) == ["per 100 g"] + zip(names, values).map { "\($0) \($1)" } + ["* Referentie-inname"])
    }

    @Test func aLabelWrittenInOneLineIsRead() {
        let label = NutritionLabel.read([
            "Nährwerte pro 100 g: Energie 1554 kJ / 371 kcal, Fett 12 g, davon gesättigte Fettsäuren 1,2 g, "
                + "Kohlenhydrate 55 g, davon Zucker 20 g, Eiweiß 7 g, Salz 0,4 g",
        ])
        #expect(label.kcal == 371)
        #expect(label.fat == 12)
        #expect(label.saturatedFat == 1.2)
        #expect(label.carbs == 55)
        #expect(label.sugars == 20)
        #expect(label.protein == 7)
        #expect(label.salt == 0.4)
        #expect(NutritionLabel.read(["Eiwit per 100 g: 9 g"]).protein == 9)
    }

    @Test func theIngredientsAboveTheTableDoNotCount() {
        let label = NutritionLabel.read([
            "Ingrediënten: havermout, plantaardige vetten 12%, melkeiwit 3%",
            "Per portie (30 g): 112 kcal",
            "Voedingswaarde per 100 g",
            "Energie 1569 kJ / 373 kcal",
            "Vetten 7,0 g",
            "Eiwitten 9,2 g",
        ])
        #expect(label.fat == 7)
        #expect(label.protein == 9.2)
        #expect(label.kcal == 373)
        #expect(label.servingSize == 30)
        #expect(NutritionLabel.read(["Fat 9.0g 13%"]).fat == 9)
    }

    @Test func onlyARealPortionIsTheServingSize() {
        #expect(NutritionLabel.read(["Bevat 4 porties. Voedingswaarde per 100 g"]).servingSize == nil)
        #expect(NutritionLabel.read(["Per portion Per 100 g"]).servingSize == nil)
        #expect(NutritionLabel.read(["Per serving: Fat 2.1g"]).servingSize == nil)
        #expect(NutritionLabel.read(["Per 30g serving"]).servingSize == 30)
    }

    @Test func aPowderMadeWithMilkIsNotADrink() {
        #expect(NutritionLabel.read(["Voedingswaarde per 100 g", "bereid met 100 ml melk"]).isMillilitre == false)
        #expect(NutritionLabel.read(["per 100 g as sold / per 100 ml prepared"]).isMillilitre == false)
    }

    @Test func frenchAndBelgianLabelsAreRead() {
        let label = NutritionLabel.read([
            "Valeurs nutritionnelles pour 100 g",
            "Énergie 1569 kJ / 373 kcal",
            "Matières grasses 7 g",
            "dont acides gras saturés 1,3 g",
            "Glucides 62 g",
            "dont sucres 21 g",
            "Fibres alimentaires 7,5 g",
            "Protéines 9,2 g",
            "Sel 0,48 g",
        ])
        #expect(label.kcal == 373)
        #expect(label.fat == 7)
        #expect(label.saturatedFat == 1.3)
        #expect(label.carbs == 62)
        #expect(label.sugars == 21)
        #expect(label.fiber == 7.5)
        #expect(label.protein == 9.2)
        #expect(label.salt == 0.48)
        #expect(NutritionLabel.read(["Graisses 7 g"]).fat == 7)
        #expect(NutritionLabel.read(["EiweiB 7,0 g"]).protein == 7)
    }

    @Test func unsaturatedFatAndStarchAreNotTakenForOtherRows() {
        let label = NutritionLabel.read([
            "Vet 7 g", "waarvan enkelvoudig onverzadigd 4 g", "waarvan verzadigd 1,3 g",
            "Koolhydraten 62 g", "waarvan zetmeel 40 g", "waarvan suikers 21 g",
        ])
        #expect(label.fat == 7)
        #expect(label.saturatedFat == 1.3)
        #expect(label.carbs == 62)
        #expect(label.sugars == 21)
    }

    @Test func sodiumGivesTheSaltAndDigitsReadAsLettersAreRead() {
        #expect(NutritionLabel.read(["Natrium 0,4 g"]).salt == 1)
        #expect(NutritionLabel.read(["Sodium 400 mg"]).salt == 1)
        #expect(NutritionLabel.read(["Zout 0,8 g", "Natrium 0,4 g"]).salt == 0.8)
        let label = NutritionLabel.read(["Vet O,5 g", "Zout l,3 g"])
        #expect(label.fat == 0.5)
        #expect(label.salt == 1.3)
    }

    @Test func aValueLeftOutAsksForACheck() {
        #expect(NutritionLabel.read(["Energie 373 kcal", "Vet 700 g"]).needsCheck)
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
