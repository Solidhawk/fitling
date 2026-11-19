import CoreGraphics
import SwiftUI
import Testing
import FitlingCore
@testable import Fitling

/// The partners are drawn from flat parts. The catalog shows them side by side, so they share one
/// drawing space and stand on one baseline; light and shadow only ever fall on the body.
struct FigureTests {
    @Test(arguments: Species.allCases)
    func everyPartnerHasExactlyOneBody(_ species: Species) {
        #expect(species.parts.filter { $0.role == .body }.count == 1)
    }

    @Test(arguments: Species.allCases)
    func shadingIsDrawnAfterTheBodyItFallsOn(_ species: Species) {
        let parts = species.parts
        let body = parts.firstIndex { $0.role == .body }
        let shading = parts.indices.filter { parts[$0].role == .shading }
        #expect(!shading.isEmpty)
        #expect(shading.allSatisfy { index in body.map { index > $0 } ?? false })
    }

    @Test(arguments: Species.allCases)
    func partnersStayInsideTheirDrawingSpace(_ species: Species) {
        let parts = species.parts
        let body = parts.first { $0.role == .body }?.path.boundingRect ?? .null
        // Shading is clipped to the body, so only the part inside the body is drawn.
        let bounds = parts
            .map { $0.role == .shading ? $0.path.boundingRect.intersection(body) : $0.path.boundingRect }
            .reduce(CGRect.null) { $0.union($1) }
        #expect(!bounds.isNull)
        #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 100 && bounds.maxY <= 100)
        #expect(FigurePart.groundShadow.maxY <= 100)
    }

    @Test(arguments: Species.allCases)
    func partnersStandOnTheSameBaseline(_ species: Species) {
        let outline = species.parts
            .filter { $0.role == .silhouette || $0.role == .body }
            .map(\.path.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
        #expect(abs(outline.maxY - FigurePart.baseline) < 0.5)
    }
}
