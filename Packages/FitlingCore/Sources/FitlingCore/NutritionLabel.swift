#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The nutrition table on a package, as the camera reads it (TASKS 2.8, ARCHITECTURE §5): the values per 100 g or
/// 100 ml, from labels in Dutch, English, German and French. What is read fills the form for an own product; the
/// user checks it before saving.
public struct NutritionLabel: Sendable, Equatable {
    public var kcal: Double?
    public var fat: Double?
    public var saturatedFat: Double?
    public var carbs: Double?
    public var sugars: Double?
    public var fiber: Double?
    public var protein: Double?
    public var salt: Double?
    /// The table says "per 100 ml": a drink.
    public var isMillilitre = false
    /// The portion the table names, such as "per portie (30 g)".
    public var servingSize: Double?

    public init() {}

    /// Energy and the three macros known, and 4·protein + 4·carbs + 9·fat more than 25 % and more than 30 kcal away
    /// from the energy: something was read wrong, or the label itself is wrong (ARCHITECTURE §5.1).
    public var needsCheck: Bool {
        guard let kcal, let protein, let carbs, let fat else { return false }
        let difference = abs(4 * protein + 4 * carbs + 9 * fat - kcal)
        return difference > 0.25 * kcal && difference > 30
    }

    /// The form with what was read in the fields that are still empty: what the user typed stays.
    public func filling(_ draft: OwnProductDraft) -> OwnProductDraft {
        var filled = draft
        filled.kcal = draft.kcal ?? kcal
        filled.protein = draft.protein ?? protein
        filled.carbs = draft.carbs ?? carbs
        filled.fat = draft.fat ?? fat
        filled.servingSize = draft.servingSize ?? servingSize
        filled.isMillilitre = draft.isMillilitre || isMillilitre
        return filled
    }

    // MARK: Lines

    /// A piece of text with its place: `x` from the left and `y` from the top, both as a part of the photo.
    public struct Piece: Sendable, Equatable {
        public let text: String
        public let x: Double
        public let y: Double
        public let height: Double

        public init(text: String, x: Double, y: Double, height: Double) {
            self.text = text
            self.x = x
            self.y = y
            self.height = height
        }
    }

    /// The pieces of one line joined from left to right, the lines from top to bottom. A table gives the name and the
    /// values of a row as separate pieces; they are on one line when their middles are less than half a line apart.
    public static func rows(_ pieces: [Piece]) -> [String] {
        var lines: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.y < $1.y }) {
            if let first = lines.last?.first, abs(piece.y - first.y) < max(piece.height, first.height) / 2 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines.map { line in line.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }

    // MARK: Reading

    /// The values in the lines of a nutrition table. Of each row the first value counts: the column per 100 g comes
    /// first on European labels (EU 1169/2011). A value that cannot be true per 100 g is left out.
    public static func read(_ lines: [String]) -> NutritionLabel {
        var label = NutritionLabel()
        var kilojoules: Double?
        for line in lines {
            let text = line.folded
            let words = Self.words(text)
            let numbers = Self.numbers(text)
            if text.contains("100 ml") || text.contains("100ml") { label.isMillilitre = true }
            if label.servingSize == nil, let serving = Self.servingSize(words: words, text: text) { label.servingSize = serving }
            guard let nutrient = Nutrient.allCases.first(where: { $0.matches(words) }) else {
                // "373 kcal" on its own row, under "Energie 1569 kJ".
                if label.kcal == nil, let kcal = numbers.first(where: { $0.unit == "kcal" }) { label.kcal = kcal.value }
                continue
            }
            if nutrient == .energy {
                if label.kcal == nil, let kcal = Self.energy(numbers, unit: "kcal", rowSays: text.contains("kcal")) { label.kcal = kcal }
                if kilojoules == nil, let kj = Self.energy(numbers, unit: "kj", rowSays: !text.contains("kcal") && text.contains("kj")) { kilojoules = kj }
                continue
            }
            guard let first = numbers.first else { continue }
            let grams = first.unit == "mg" ? first.value / 1000 : first.value
            guard (0...100).contains(grams) else { continue }
            label.set(nutrient, grams)
        }
        if label.kcal == nil, let kilojoules { label.kcal = (kilojoules / 4.184 * 10).rounded() / 10 }
        if let kcal = label.kcal, !Limits.kcalPer100.contains(kcal) { label.kcal = nil }
        return label
    }

    private mutating func set(_ nutrient: Nutrient, _ grams: Double) {
        switch nutrient {
        case .energy: break
        case .saturatedFat: saturatedFat = saturatedFat ?? grams
        case .sugars: sugars = sugars ?? grams
        case .fiber: fiber = fiber ?? grams
        case .protein: protein = protein ?? grams
        case .salt: salt = salt ?? grams
        case .fat: fat = fat ?? grams
        case .carbs: carbs = carbs ?? grams
        }
    }

    /// The nutrients, in the order they are tried: "waarvan verzadigde vetzuren" is saturated fat before it is fat,
    /// and "waarvan suikers" is sugars before anything else.
    private enum Nutrient: CaseIterable {
        case energy, saturatedFat, sugars, fiber, protein, salt, fat, carbs

        /// Long words are found inside compounds ("voedingsvezel"); short ones only at the start of a word, so "vet"
        /// is not found in "verzadigd". "sel" (French salt) is a word of its own, not the start of "selen".
        private var keywords: (inside: [String], start: [String], whole: [String]) {
            switch self {
            case .energy: (["energ", "brennwert"], [], [])
            case .saturatedFat: (["verzadigd", "satur", "gesattigt"], [], [])
            case .sugars: (["suiker", "sugar", "zucker", "sucre"], [], [])
            case .fiber: (["vezel", "fibre", "fiber", "ballaststoff"], [], [])
            case .protein: (["eiwit", "protein", "eiweiß", "eiweiss"], [], [])
            case .salt: ([], ["zout", "salt", "salz"], ["sel"])
            case .fat: (["lipide", "grasse"], ["vet", "fat", "fett"], [])
            case .carbs: (["koolhydra", "carbohydrat", "kohlenhydrat", "glucide"], [], [])
            }
        }

        func matches(_ words: [String]) -> Bool {
            let keywords = keywords
            return words.contains { word in
                keywords.inside.contains { word.contains($0) }
                    || keywords.start.contains { word.hasPrefix($0) }
                    || keywords.whole.contains(word)
            }
        }
    }

    private static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter }.map(String.init)
    }

    /// The energy of a row in `unit`: the number written with that unit, or the first number when the row only names
    /// the unit, as in "Energie (kcal) 373".
    private static func energy(_ numbers: [(value: Double, unit: String)], unit: String, rowSays: Bool) -> Double? {
        if let written = numbers.first(where: { $0.unit == unit }) { return written.value }
        return rowSays ? numbers.first?.value : nil
    }

    /// "per portie (30 g)", "portion 30g", "1 serving = 30 g": the first number in grams or millilitres after the word.
    private static func servingSize(words: [String], text: String) -> Double? {
        let names = ["portie", "portion", "serving"]
        guard let name = names.first(where: { name in words.contains { $0.hasPrefix(name) } }),
              let start = text.indices.first(where: { text[$0...].hasPrefix(name) }) else {
            return nil
        }
        let after = numbers(String(text[text.index(start, offsetBy: name.count)...]))
        guard let first = after.first(where: { $0.unit == "g" || $0.unit == "ml" }), first.value > 0, first.value < 100_000 else {
            return nil
        }
        return first.value
    }

    /// Every number in the text with the letters right after it: "1046kj/250kcal" is 1046 kj and 250 kcal, "7,0 g"
    /// is 7.0 g. A comma or a point between digits is the decimal sign.
    private static func numbers(_ text: String) -> [(value: Double, unit: String)] {
        let characters = Array(text)
        var found: [(value: Double, unit: String)] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber, characters[index].isASCII else {
                index += 1
                continue
            }
            var digits = ""
            while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                digits.append(characters[index])
                index += 1
            }
            if index + 1 < characters.count, characters[index] == "," || characters[index] == ".",
               characters[index + 1].isASCII, characters[index + 1].isNumber {
                digits.append(".")
                index += 1
                while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                    digits.append(characters[index])
                    index += 1
                }
            }
            var unitIndex = index
            while unitIndex < characters.count, characters[unitIndex] == " " { unitIndex += 1 }
            var unit = ""
            while unitIndex < characters.count, characters[unitIndex].isLetter {
                unit.append(characters[unitIndex])
                unitIndex += 1
            }
            if let value = Double(digits) { found.append((value, unit)) }
        }
        return found
    }
}
