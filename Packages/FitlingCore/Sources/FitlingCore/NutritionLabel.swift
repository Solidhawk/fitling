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
    /// The table is per 100 ml: a drink.
    public var isMillilitre = false
    /// The portion the label names, such as "per portie (30 g)".
    public var servingSize: Double?
    /// A value was read that cannot be true per 100 g, and was left out.
    public var leftSomethingOut = false

    public init() {}

    /// Something was left out, or energy and the three macros are known and 4·protein + 4·carbs + 9·fat is more than
    /// 25 % and more than 30 kcal away from the energy: read wrong, or the label is wrong (ARCHITECTURE §5.1).
    public var needsCheck: Bool {
        if leftSomethingOut { return true }
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

    /// A piece of text with its place: `x` from the left and `y` from the top, both as a part of the photo, and the
    /// slope of its baseline (down per width) when the photo was taken at an angle.
    public struct Piece: Sendable, Equatable {
        public let text: String
        public let x: Double
        public let y: Double
        public let height: Double
        public let slope: Double

        public init(text: String, x: Double, y: Double, height: Double, slope: Double = 0) {
            self.text = text
            self.x = x
            self.y = y
            self.height = height
            self.slope = slope
        }
    }

    /// The pieces of one line joined from left to right, the lines from top to bottom. A table gives the name and the
    /// values of a row as separate pieces; they are on one line when, straightened by the slope of the photo, their
    /// middles are less than half the height of the tallest of them apart.
    public static func rows(_ pieces: [Piece]) -> [String] {
        // Vision gives the longer pieces of a tilted photo a tilted box, with the slope of the photo, but a short piece
        // an upright one: a slope of 0 says nothing. The slope is the middle one of the others, once at least three
        // pieces agree with it; a single stamp at an angle on a straight photo does not tilt the table. How well the
        // pieces line up cannot decide it: tilted by one row over the columns, each name pairs with the value of the
        // row above in fewer lines than the true slope gives.
        let slopes = pieces.map(\.slope).filter { abs($0) > 0.002 }.sorted()
        let median = slopes.isEmpty ? 0 : slopes[slopes.count / 2]
        let slope = slopes.filter { abs($0 - median) <= 0.02 }.count >= 3 ? median : 0
        return lines(pieces, slope: slope).map { line in line.pieces.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }

    private struct Line {
        var pieces: [Piece]
        /// The middles of its pieces, straightened.
        var middles: [Double]

        var middle: Double { middles.reduce(0, +) / Double(middles.count) }
        var height: Double { pieces.map(\.height).max() ?? 0 }
    }

    private static func lines(_ pieces: [Piece], slope: Double) -> [Line] {
        let straight = pieces.map { (piece: $0, y: $0.y - slope * $0.x) }.sorted { $0.y < $1.y }
        var lines: [Line] = []
        for item in straight {
            if let line = lines.last, abs(item.y - line.middle) < max(item.piece.height, line.height) / 2 {
                lines[lines.count - 1].pieces.append(item.piece)
                lines[lines.count - 1].middles.append(item.y)
            } else {
                lines.append(Line(pieces: [item.piece], middles: [item.y]))
            }
        }
        return lines
    }

    // MARK: Reading

    /// The values in the lines of a nutrition table. A value belongs to the name before it, so a label written as one
    /// line reads too; of a row with columns the first counts, the one per 100 g (EU 1169/2011). Reading starts at the
    /// heading or the energy row, so the ingredients above the table do not count; a percentage and the "100" of
    /// "per 100 g" are never a value. A value that cannot be true per 100 g is left out.
    public static func read(_ lines: [String]) -> NutritionLabel {
        var label = NutritionLabel()
        let tokenized = lines.map { Self.tokens(Self.digitsForLetters($0.folded)) }
        let start = tokenized.firstIndex(where: Self.startsTable) ?? 0
        var reading = Reading()
        for (index, tokens) in tokenized.enumerated() {
            if label.servingSize == nil, let serving = Self.servingSize(tokens) { label.servingSize = serving }
            guard index >= start else { continue }
            reading.line(tokens)
        }
        let table = tokenized[start...].flatMap { $0 }
        if let hundred = table.first(where: { $0.number?.value == 100 && ["g", "ml"].contains($0.number?.unit ?? "") }) {
            label.isMillilitre = hundred.number?.unit == "ml"
        }
        label.kcal = reading.kcal ?? reading.lonelyKcal ?? reading.kilojoules.map { ($0 / 4.184 * 10).rounded() / 10 }
        if let kcal = label.kcal, !Limits.kcalPer100.contains(kcal) {
            label.kcal = nil
            label.leftSomethingOut = true
        }
        label.fat = reading.grams[.fat]
        label.saturatedFat = reading.grams[.saturatedFat]
        label.carbs = reading.grams[.carbs]
        label.sugars = reading.grams[.sugars]
        label.fiber = reading.grams[.fiber]
        label.protein = reading.grams[.protein]
        label.salt = reading.grams[.salt] ?? reading.grams[.sodium].map { ($0 * 2.5 * 100).rounded() / 100 }
        label.leftSomethingOut = label.leftSomethingOut || reading.leftSomethingOut
        return label
    }

    /// What has been read so far, line by line.
    private struct Reading {
        var grams: [Nutrient: Double] = [:]
        var kcal: Double?
        var kilojoules: Double?
        /// "373 kcal" on a row of its own: used when the energy row gave none.
        var lonelyKcal: Double?
        var leftSomethingOut = false
        /// The ingredients came after the table: "suiker, zout, conserveermiddel E250" names no values.
        var isFinished = false

        /// The heading of the ingredients, folded, in the languages of the labels.
        private static let ingredients: Set<String> = ["ingredienten", "ingredients", "zutaten"]

        mutating func line(_ tokens: [Token]) {
            guard !isFinished else { return }
            // The names since the last value: "verzadigde vetzuren" is one name, saturated fat.
            var named: [Nutrient] = []
            var energyNumbers: [Number] = []
            var energyUnits: [String] = []
            var previousWord = ""
            reading: for token in tokens {
                switch token {
                case let .word(word):
                    previousWord = word
                    // Ingredients above the table come before any value and are passed by.
                    if Self.ingredients.contains(word), !grams.isEmpty || kcal != nil || kilojoules != nil {
                        isFinished = true
                        break reading
                    }
                    guard let nutrient = Nutrient.named(by: word) else { continue }
                    if named.first == .energy, !energyNumbers.isEmpty, nutrient != .energy {
                        finishEnergy(energyNumbers, energyUnits)
                        energyNumbers = []
                        energyUnits = []
                        named = []
                    }
                    if nutrient == .energy, word == "kj" || word == "kcal" { energyUnits.append(word) }
                    named.append(nutrient)
                    named.sort { $0.rank < $1.rank }
                case let .number(number):
                    defer { previousWord = "" }
                    // "per 100 g" and "13 %" name the column or the reference intake, not a value.
                    if ["per", "pro", "je", "pour"].contains(previousWord) || number.unit == "%" { continue }
                    guard let nutrient = named.first else {
                        // Not the "2000 kcal" of the reference intake in a column heading: no product has that per 100 g.
                        if number.unit == "kcal", Limits.kcalPer100.contains(number.value) { lonelyKcal = lonelyKcal ?? number.value }
                        continue
                    }
                    if nutrient == .energy {
                        energyNumbers.append(number)
                        continue
                    }
                    named = []
                    guard nutrient != .other else { continue }
                    let value = number.unit == "mg" ? number.value / 1000 : number.value
                    guard (0...100).contains(value) else {
                        // Misread, unless the table gave this one already: "zout, conserveermiddel E250" in the
                        // ingredients under it is no second value.
                        if grams[nutrient] == nil { leftSomethingOut = true }
                        continue
                    }
                    if grams[nutrient] == nil { grams[nutrient] = value }
                }
            }
            if named.first == .energy { finishEnergy(energyNumbers, energyUnits) }
        }

        /// The numbers of an energy row: with their unit written after them, or in the order the row names its units
        /// ("Energie kJ/kcal 1554/371"), or as a pair whose ratio is that of kJ to kcal.
        mutating func finishEnergy(_ numbers: [Number], _ units: [String]) {
            var kj = numbers.first { $0.unit == "kj" }.map(\.kilojoules)
            var found = numbers.first { $0.unit == "kcal" }?.value
            let bare = numbers.filter { $0.unit.isEmpty }
            if !units.isEmpty {
                for (unit, number) in zip(units, bare) {
                    if unit == "kj" { kj = kj ?? number.kilojoules } else { found = found ?? number.value }
                }
            } else if kj == nil, found == nil, bare.count >= 2, bare[1].value > 0, (3.8...4.6).contains(bare[0].value / bare[1].value) {
                kj = bare[0].kilojoules
                found = bare[1].value
            }
            kcal = kcal ?? found
            kilojoules = kilojoules ?? kj
        }
    }

    /// The nutrients, in the order they win when a name has more than one: "onverzadigde vetzuren" is none of them,
    /// "verzadigde vetzuren" is saturated fat before it is fat, "waarvan suikers" is sugars.
    private enum Nutrient: CaseIterable {
        /// Unsaturated fat, starch, polyols: a value of its own that belongs to no field.
        case other
        case energy, saturatedFat, sugars, fiber, protein, salt, sodium, fat, carbs

        var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        /// Long words are found inside compounds ("voedingsvezel"); short ones only at the start of a word, so "vet"
        /// is not found in "verzadigd". "sel" (French salt) is a word of its own, not the start of "selen".
        private var keywords: (inside: [String], start: [String], whole: [String]) {
            switch self {
            case .other: (["onverzadig", "unsatur", "ungesattig", "insatur", "zetmeel", "starch", "starke", "amidon", "polyol"], [], [])
            case .energy: (["energ", "brennwert"], [], ["kj", "kcal"])
            case .saturatedFat: (["verzadigd", "satur", "gesattigt"], [], [])
            case .sugars: (["suiker", "sugar", "zucker", "sucre"], [], [])
            case .fiber: (["vezel", "fibre", "fiber", "ballaststoff"], [], [])
            case .protein: (["eiwit", "protein", "eiwei"], [], [])
            case .salt: ([], ["zout", "salt", "salz"], ["sel"])
            case .sodium: (["natrium", "sodium"], [], [])
            case .fat: (["lipide", "grasse", "graisse"], ["vet", "fat", "fett"], [])
            case .carbs: (["koolhydra", "carbohydrat", "kohlenhydrat", "glucide"], [], [])
            }
        }

        static func named(by word: String) -> Nutrient? {
            allCases.first { nutrient in
                let keywords = nutrient.keywords
                return keywords.inside.contains { word.contains($0) } || keywords.start.contains { word.hasPrefix($0) }
                    || keywords.whole.contains(word)
            }
        }
    }

    // MARK: Words and numbers

    struct Number: Equatable {
        let value: Double
        let unit: String
        /// Digits after the decimal sign: "1.554 kJ" has three, a thousand separator.
        let decimals: Int

        /// kJ per 100 g is often above a thousand; "1.554" before kJ is then 1554, not 1.554.
        var kilojoules: Double { decimals == 3 && value < 10 ? value * 1000 : value }
    }

    enum Token: Equatable {
        case word(String)
        case number(Number)

        var number: Number? {
            if case let .number(number) = self { number } else { nil }
        }
    }

    /// The table starts at its heading ("Voedingswaarde per 100 g", "Nutrition", "Nährwerte") or at the energy row.
    private static func startsTable(_ tokens: [Token]) -> Bool {
        let words = tokens.compactMap { token -> String? in if case let .word(word) = token { word } else { nil } }
        let headings = ["voedingswaarde", "nutrition", "nahrwert", "valeurs", "typical"]
        if words.contains(where: { word in headings.contains { word.hasPrefix($0) } }) { return true }
        if words.contains(where: { Nutrient.named(by: $0) == .energy }) { return true }
        return zip(tokens, tokens.dropFirst()).contains { first, second in
            if case let .word(word) = first, ["per", "pro", "je", "pour"].contains(word), second.number?.value == 100 { true } else { false }
        }
    }

    /// "per portie (30 g)", "1 serving = 30 g", "Per 30g serving": grams or millilitres right after the word, before the
    /// next "per" or name, or right before it. Never the 100 of "per 100 g".
    private static func servingSize(_ tokens: [Token]) -> Double? {
        let names = ["portie", "portion", "serving"]
        guard let index = tokens.firstIndex(where: { token in
            if case let .word(word) = token { names.contains { word.hasPrefix($0) } } else { false }
        }) else { return nil }
        func portion(_ token: Token) -> Double? {
            guard let number = token.number, number.unit == "g" || number.unit == "ml", number.value != 100,
                  number.value > 0, number.value < 100_000 else { return nil }
            return number.value
        }
        for token in tokens[(index + 1)...] {
            if case let .word(word) = token {
                if ["per", "pro", "je", "pour"].contains(word) || Nutrient.named(by: word) != nil { break }
                continue
            }
            if let value = portion(token) { return value }
        }
        return index > 0 ? portion(tokens[index - 1]) : nil
    }

    /// A camera reads 0 as O and 1 as l or I next to digits: "O,5 g" is 0,5 g, "l,3 g" is 1,3 g. A letter only counts as
    /// a digit where it touches one and is no part of a word.
    static func digitsForLetters(_ text: String) -> String {
        let characters = Array(text)
        func isDigit(_ index: Int) -> Bool { characters.indices.contains(index) && characters[index].isASCII && characters[index].isNumber }
        func isLetter(_ index: Int) -> Bool { characters.indices.contains(index) && characters[index].isLetter }
        func isDecimal(_ index: Int) -> Bool {
            characters.indices.contains(index) && (characters[index] == "," || characters[index] == ".") && isDigit(index + 1)
        }
        var result = ""
        for (index, character) in characters.enumerated() {
            let beforeDigits = !isLetter(index - 1) && (isDigit(index + 1) || isDecimal(index + 1))
            if character == "o", beforeDigits || (isDigit(index - 1) && !isLetter(index + 1)) {
                result.append("0")
            } else if character == "l" || character == "i", beforeDigits {
                result.append("1")
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// The units a value can have, under one name each.
    private static let units: [String: String] = [
        "g": "g", "gr": "g", "gram": "g", "grams": "g", "gramm": "g", "mg": "mg", "µg": "µg", "ug": "µg", "mcg": "µg",
        "kj": "kj", "kcal": "kcal", "ml": "ml", "cl": "cl", "l": "l",
    ]

    /// Words, and numbers with a unit or "%" right after them: "1046kj/250kcal" is 1046 kj and 250 kcal, "7,0 g" is
    /// 7.0 g. A comma or a point between digits is the decimal sign.
    static func tokens(_ text: String) -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        func isDigit(_ index: Int) -> Bool { characters.indices.contains(index) && characters[index].isASCII && characters[index].isNumber }
        while index < characters.count {
            if isDigit(index) {
                var digits = ""
                while isDigit(index) {
                    digits.append(characters[index])
                    index += 1
                }
                var decimals = 0
                if index < characters.count, characters[index] == "," || characters[index] == ".", isDigit(index + 1) {
                    digits.append(".")
                    index += 1
                    while isDigit(index) {
                        digits.append(characters[index])
                        decimals += 1
                        index += 1
                    }
                }
                var unitIndex = index
                while unitIndex < characters.count, characters[unitIndex] == " " { unitIndex += 1 }
                var unit = ""
                if unitIndex < characters.count, characters[unitIndex] == "%" {
                    unit = "%"
                    unitIndex += 1
                } else {
                    var letters = ""
                    while unitIndex < characters.count, characters[unitIndex].isLetter {
                        letters.append(characters[unitIndex])
                        unitIndex += 1
                    }
                    // Only a unit: in "4 porties" the word stays a word.
                    unit = Self.units[letters] ?? ""
                }
                if !unit.isEmpty { index = unitIndex }
                if let value = Double(digits) { tokens.append(.number(Number(value: value, unit: unit, decimals: decimals))) }
            } else if characters[index].isLetter {
                var word = ""
                while index < characters.count, characters[index].isLetter {
                    word.append(characters[index])
                    index += 1
                }
                tokens.append(.word(word))
            } else {
                index += 1
            }
        }
        return tokens
    }
}
