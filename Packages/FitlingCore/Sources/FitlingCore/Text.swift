extension String {
    /// Lower case and without accents: "Crème" and "creme" are the same word. For the Latin, Greek and
    /// Cyrillic letters of `foldTable` this is exactly Unicode decomposition (NFD) without the combining marks,
    /// as Foundation gave it, but without Foundation, so the rules also build for the browser (D-24). Letters
    /// without a decomposition, such as æ, ø and ł, stay as they are, as they would with NFD.
    var folded: String {
        var scalars = String.UnicodeScalarView()
        for scalar in lowercased().unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            if let base = Self.foldTable[scalar] {
                scalars.append(contentsOf: base.unicodeScalars)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Without white space and newlines at the start and end, as Foundation's
    /// `trimmingCharacters(in: .whitespacesAndNewlines)`.
    func trimmingWhitespace() -> String {
        guard let first = firstIndex(where: { !$0.isWhitespace }), let last = lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(self[first...last])
    }

    /// At most `limit` Unicode scalars, cut between whole characters. Postgres counts code points in `char_length`, so
    /// a flag takes two of the limit; Swift's `count` would let a name of flags through that the database refuses.
    public func limited(toScalars limit: Int) -> String {
        var result = ""
        var scalars = 0
        for character in self {
            scalars += character.unicodeScalars.count
            guard scalars <= limit else { break }
            result.append(character)
        }
        return result
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
}
