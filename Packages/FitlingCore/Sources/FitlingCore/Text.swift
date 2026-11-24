extension String {
    /// Lower case and without accents: "Crème" and "creme" are the same word. Gives what Unicode
    /// decomposition (NFD) without the combining marks gives for the Latin letters of product names,
    /// without Foundation, so the rules also build for the browser (D-24). Letters without a decomposition,
    /// such as æ, ø and ł, stay as they are, as they would with NFD.
    var folded: String {
        var scalars = String.UnicodeScalarView()
        for scalar in lowercased().unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(Self.latinBases[scalar] ?? scalar)
        }
        return String(scalars)
    }

    /// Without spaces and tabs at the start and end; newlines and the spaces between words stay. The same
    /// as Foundation's `trimmingCharacters(in: .whitespaces)`.
    func trimmingSpaces() -> String {
        func isSpace(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy { $0 == "\t" || $0.properties.generalCategory == .spaceSeparator }
        }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) }) else { return "" }
        return String(self[first...last])
    }

    /// Lower-case Latin-1 and Latin Extended-A letters with a canonical decomposition, to their base letter.
    private static let latinBases: [Unicode.Scalar: Unicode.Scalar] = {
        let groups: [(Unicode.Scalar, String)] = [
            ("a", "àáâãäåāăą"), ("c", "çćĉċč"), ("d", "ď"), ("e", "èéêëēĕėęě"), ("g", "ĝğġģ"), ("h", "ĥ"),
            ("i", "ìíîïĩīĭį"), ("j", "ĵ"), ("k", "ķ"), ("l", "ĺļľ"), ("n", "ñńņň"), ("o", "òóôõöōŏő"), ("r", "ŕŗř"),
            ("s", "śŝşš"), ("t", "ţť"), ("u", "ùúûüũūŭůűų"), ("w", "ŵ"), ("y", "ýÿŷ"), ("z", "źżž"),
        ]
        var bases: [Unicode.Scalar: Unicode.Scalar] = [:]
        for (base, letters) in groups {
            for letter in letters.unicodeScalars { bases[letter] = base }
        }
        return bases
    }()
}
