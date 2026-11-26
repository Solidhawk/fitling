import Foundation
import Testing
@testable import FitlingCore

/// The two text helpers that replace Foundation's, so the rules build for the browser too (D-24).
@Suite struct TextTests {
    @Test func foldingDropsAccentsAndCase() {
        #expect("Crème Brûlée".folded == "creme brulee")
        #expect("Ñandú, çà, Ærø, ÿ".folded == "nandu, ca, ærø, y")
        // Already decomposed: the combining marks go too.
        #expect("Cre\u{0300}me".folded == "creme")
    }

    /// The offer matcher used to fold with Foundation's decomposition (NFD) without the combining marks. For
    /// every letter of the Latin, Greek and Cyrillic blocks `folded` must give exactly that, on iOS too.
    @Test func foldedMatchesFoundationForLatinGreekAndCyrillic() {
        func foundation(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            where scalar.properties.generalCategory != .nonspacingMark {
                scalars.append(scalar)
            }
            return String(scalars)
        }
        var different: [String] = []
        for range in [0x00C0..<0x0250, 0x0370..<0x0500, 0x1E00..<0x2000] {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let text = String(scalar)
                if text.folded != foundation(text) { different.append("U+\(String(value, radix: 16, uppercase: true)) \(text)") }
            }
        }
        #expect(different.isEmpty, "\(different.count) letters differ, e.g. \(different.prefix(10).joined(separator: ", "))")
        #expect("Phở brânză și Ελληνικό ёж".folded == foundation("Phở brânză și Ελληνικό ёж"))
    }

    @Test func trimmingSpacesKeepsNewlinesAndInnerSpaces() {
        #expect("\t  rode ui \u{00A0}".trimmingSpaces() == "rode ui")
        #expect("\nui".trimmingSpaces() == "\nui")
        #expect("   ".trimmingSpaces() == "")
    }
}
