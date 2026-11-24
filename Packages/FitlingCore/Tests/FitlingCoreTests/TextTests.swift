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

    @Test func trimmingSpacesKeepsNewlinesAndInnerSpaces() {
        #expect("\t  rode ui \u{00A0}".trimmingSpaces() == "rode ui")
        #expect("\nui".trimmingSpaces() == "\nui")
        #expect("   ".trimmingSpaces() == "")
    }
}
