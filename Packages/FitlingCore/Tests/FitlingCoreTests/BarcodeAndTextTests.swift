import Foundation
import Testing
@testable import FitlingCore

@Suite struct BarcodeTests {
    @Test func keepsValidEan13AndEan8AsTheyAre() {
        #expect(Barcode.normalized("4006381333931") == "4006381333931")
        #expect(Barcode.normalized("73513537") == "73513537")
    }

    @Test func storesUpcAAsThirteenDigitsWithALeadingZero() {
        #expect(Barcode.normalized("036000291452") == "0036000291452")
        // The same package scanned as EAN-13 gives the same key.
        #expect(Barcode.normalized("0036000291452") == "0036000291452")
    }

    @Test func ignoresSpacesAroundAndInsideTheCode() {
        #expect(Barcode.normalized(" 4006381 333931\n") == "4006381333931")
    }

    @Test func rejectsAWrongCheckDigit() {
        #expect(Barcode.normalized("4006381333932") == nil)
        #expect(Barcode.normalized("73513538") == nil)
    }

    @Test func rejectsOtherLengthsAndNonDigits() {
        #expect(Barcode.normalized("") == nil)
        #expect(Barcode.normalized("1234567") == nil)
        #expect(Barcode.normalized("12345678901234") == nil)
        #expect(Barcode.normalized("40063813339a1") == nil)
        #expect(Barcode.normalized("٤٠٠٦٣٨١٣٣٣٩٣١") == nil)
    }
}

@Suite struct LocalizedTextTests {
    let bread = LocalizedText(["nl": "Brood", "en": "Bread", "fr": "Pain"])

    @Test func picksTheFirstPreferredLanguageThatHasAText() {
        #expect(bread.text(preferring: ["de", "fr"]) == "Pain")
        #expect(bread.text(preferring: ["nl-NL"]) == "Brood")
        #expect(bread.text(preferring: ["EN_us"]) == "Bread")
    }

    @Test func fallsBackToEnglishThenDutchThenAnything() {
        #expect(bread.text(preferring: ["de"]) == "Bread")
        #expect(LocalizedText(["nl": "Brood", "fr": "Pain"]).text(preferring: ["de"]) == "Brood")
        #expect(LocalizedText(["it": "Pane", "fr": "Pain"]).text(preferring: ["de"]) == "Pain")
        #expect(LocalizedText().text(preferring: ["de"]) == "")
    }

    @Test func skipsEmptyTexts() {
        #expect(LocalizedText(["de": "", "nl": "Brood"]).text(preferring: ["de"]) == "Brood")
        #expect(LocalizedText(["de": ""]).isEmpty)
        #expect(bread.isEmpty == false)
    }

    @Test func encodesAsAPlainJsonObject() throws {
        let data = try JSONEncoder().encode(LocalizedText(["nl": "Brood"]))
        #expect(String(decoding: data, as: UTF8.self) == "{\"nl\":\"Brood\"}")
        #expect(try JSONDecoder().decode(LocalizedText.self, from: data) == LocalizedText(["nl": "Brood"]))
    }

    @Test func survivesTheLocalStoreAsJson() {
        #expect(LocalizedText(json: bread.json) == bread)
        #expect(LocalizedText(json: Data("geen json".utf8)) == LocalizedText())
    }
}
