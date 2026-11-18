import CoreGraphics
import SwiftUI
import Testing
@testable import Fitling

/// The catalog shows the four figures side by side, so they share one drawing space and stand on
/// one baseline.
struct FigureTests {
    @Test(arguments: Species.allCases)
    func everyFigureHasASilhouette(_ species: Species) {
        #expect(species.parts.contains { $0.keyline })
    }

    @Test(arguments: Species.allCases)
    func figuresStayInsideTheirDrawingSpace(_ species: Species) {
        let bounds = species.parts.map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
        #expect(!bounds.isNull)
        // The keyline is drawn on the outline, so half of it falls outside the parts.
        let margin = FigurePart.keylineWidth / 2
        #expect(bounds.minX >= margin && bounds.minY >= margin)
        #expect(bounds.maxX <= 100 - margin && bounds.maxY <= 100 - margin)
    }

    @Test(arguments: Species.allCases)
    func figuresStandOnTheSameBaseline(_ species: Species) {
        let silhouette = species.parts.filter(\.keyline).map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
        #expect(abs(silhouette.maxY - FigurePart.baseline) < 0.5)
    }
}
